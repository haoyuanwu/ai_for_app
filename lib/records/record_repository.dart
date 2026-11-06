import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'extracted_record.dart';
import 'record_confirmation.dart';
import 'phone_record.dart';
import 'record_fields.dart';
import 'duplicate_bill.dart';

class RecordRepository {
  RecordRepository(this.db);
  final Database db;
  static Future<void> create(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE records (id INTEGER PRIMARY KEY AUTOINCREMENT, source_id TEXT NOT NULL, ordinal INTEGER NOT NULL, kind TEXT NOT NULL, payload TEXT NOT NULL, status TEXT NOT NULL, error TEXT, created_at TEXT NOT NULL, UNIQUE(source_id, ordinal))',
    );
    await db.execute(
      'CREATE TABLE extractions (source_id TEXT PRIMARY KEY, extracted_at TEXT NOT NULL)',
    );
  }

  static Future<void> createProposals(DatabaseExecutor db) async {
    await db.execute(
      "CREATE TABLE record_proposals (id INTEGER PRIMARY KEY AUTOINCREMENT, source_id TEXT NOT NULL UNIQUE, payload TEXT NOT NULL, status TEXT NOT NULL, context TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, decided_at TEXT)",
    );
  }

  Future<List<RecordProposal>> proposals({
    bool refreshDuplicates = false,
  }) async {
    final rows = await db.query('record_proposals', orderBy: 'id ASC');
    final proposals = rows.map(RecordProposal.fromRow).toList();
    if (!refreshDuplicates) return proposals;
    return [
      for (final p in proposals)
        p.status == 'pending' &&
                p.items.any((item) => item['kind'] == 'expense')
            ? await refreshDuplicateWarnings(p.id)
            : p,
    ];
  }

  static Future<Set<int>> _duplicateIds(DatabaseExecutor db, Map item) async {
    if (item['kind'] != 'expense') return {};
    final rows = await db.query(
      'records',
      columns: ['id', 'payload'],
      where: 'kind = ?',
      whereArgs: ['expense'],
    );
    return {
      for (final row in rows)
        if (DuplicateBill.matches(
          item,
          jsonDecode(row['payload'] as String) as Map,
        ))
          row['id'] as int,
    };
  }

  Future<RecordProposal> refreshDuplicateWarnings(int id) =>
      db.transaction((txn) async {
        final rows = await txn.query(
          'record_proposals',
          where: 'id = ?',
          whereArgs: [id],
        );
        final proposal = RecordProposal.fromRow(rows.single);
        if (proposal.status != 'pending') return proposal;
        for (final item in proposal.items) {
          item.remove('duplicateRecordIds');
          if (item['kind'] != 'expense') continue;
          final ids = await _duplicateIds(txn, item);
          if (ids.isNotEmpty) item['duplicateRecordIds'] = ids.toList()..sort();
        }
        final payload = jsonEncode(proposal.items);
        if (payload != rows.single['payload']) {
          await txn.update(
            'record_proposals',
            {'payload': payload},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        return proposal;
      });
  Future<int> propose(
    String source,
    List<ExtractedRecord> items, {
    String context = '',
  }) => db.transaction((txn) async {
    if ((await txn.query(
      'extractions',
      where: 'source_id = ?',
      whereArgs: [source],
    )).isNotEmpty) {
      return 0;
    }
    if (items.isNotEmpty) {
      await txn.insert('record_proposals', {
        'source_id': source,
        'context': context,
        'payload': jsonEncode(items.map((r) => r.toJson()).toList()),
        'status': 'pending',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
    await txn.insert('extractions', {
      'source_id': source,
      'extracted_at': DateTime.now().toUtc().toIso8601String(),
    });
    return items.length;
  });

  /// An earlier empty extraction may be retried without touching saved drafts.
  Future<void> retryEmptyExtraction(String sourceId) =>
      db.transaction((txn) async {
        for (final table in ['record_proposals', 'records']) {
          if ((await txn.query(
            table,
            columns: ['id'],
            where: 'source_id = ?',
            whereArgs: [sourceId],
            limit: 1,
          )).isNotEmpty) {
            return;
          }
        }
        await txn.delete(
          'extractions',
          where: 'source_id = ?',
          whereArgs: [sourceId],
        );
      });

  Future<void> revise(
    int id,
    String updateSource,
    String context,
    List<ExtractedRecord> items,
  ) => db.transaction((txn) async {
    final row = await txn.query(
      'record_proposals',
      where: 'id = ? AND status = ?',
      whereArgs: [id, 'pending'],
    );
    if (row.isEmpty) throw StateError('该批内容已经处理，请重新提出记录');
    if ((await txn.query(
      'extractions',
      where: 'source_id = ?',
      whereArgs: [updateSource],
    )).isNotEmpty) {
      return;
    }
    if (items.isEmpty) throw StateError('未识别到更新后的内容，请具体说明要补充或修改的字段');
    await txn.update(
      'record_proposals',
      {
        'payload': jsonEncode(items.map((r) => r.toJson()).toList()),
        'context': context,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await txn.insert('extractions', {
      'source_id': updateSource,
      'extracted_at': DateTime.now().toUtc().toIso8601String(),
    });
  });
  Future<List<int>> decide(
    int id, {
    required bool accept,
    Set<int> allowedDuplicateIds = const {},
  }) => db.transaction((txn) async {
    final rows = await txn.query(
      'record_proposals',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty || rows.single['status'] != 'pending') return <int>[];
    final proposal = RecordProposal.fromRow(rows.single);
    if (accept && proposal.missingFields.isNotEmpty) {
      throw StateError('请先补充：${proposal.missingFields.join('、')}');
    }
    final ids = <int>[];
    if (accept) {
      // Check against records saved before this batch; new rows in the same
      // batch must not cause an unresolvable duplicate-confirmation loop.
      for (final item in proposal.items) {
        if (!(await _duplicateIds(
          txn,
          item,
        )).every(allowedDuplicateIds.contains)) {
          throw StateError('发现相同时间、相同金额的已有账单，请查看重复提示后再次确认是否记录');
        }
      }
      for (var i = 0; i < proposal.items.length; i++) {
        final item = proposal.items[i];
        final payload = Map<String, dynamic>.from(item)
          ..remove('duplicateRecordIds');
        ids.add(
          await txn.insert('records', {
            'source_id': proposal.sourceId,
            'ordinal': i,
            'kind': item['kind'],
            'payload': jsonEncode(payload),
            'status': item['kind'] == 'reminder'
                ? (item['at'] == null ? 'needs_time' : 'pending')
                : 'saved',
            'created_at': DateTime.now().toUtc().toIso8601String(),
          }),
        );
      }
    }
    await txn.update(
      'record_proposals',
      {
        'status': accept ? 'accepted' : 'rejected',
        'decided_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    return ids;
  });

  Future<List<Map<String, Object?>>> all() =>
      db.query('records', orderBy: 'id DESC');
  Future<bool> hasExtracted(String source) async => (await db.query(
    'extractions',
    where: 'source_id = ?',
    whereArgs: [source],
  )).isNotEmpty;
  Future<List<int>> insert(String source, List<ExtractedRecord> records) =>
      db.transaction((txn) async {
        if ((await txn.query(
          'extractions',
          where: 'source_id = ?',
          whereArgs: [source],
        )).isNotEmpty) {
          return <int>[];
        }
        final ids = <int>[];
        for (var i = 0; i < records.length; i++) {
          final r = records[i];
          ids.add(
            await txn.insert('records', {
              'source_id': source,
              'ordinal': i,
              'kind': r.kind.name,
              'payload': jsonEncode(r.toJson()),
              'status': r.kind == RecordKind.reminder
                  ? (r.at == null ? 'needs_time' : 'pending')
                  : 'saved',
              'created_at': DateTime.now().toUtc().toIso8601String(),
            }),
          );
        }
        await txn.insert('extractions', {
          'source_id': source,
          'extracted_at': DateTime.now().toUtc().toIso8601String(),
        });
        return ids;
      });
  Future<Map<String, Object?>> get(int id) async =>
      (await db.query('records', where: 'id = ?', whereArgs: [id])).single;
  Future<void> status(int id, String status, [String? error]) async {
    await db.update(
      'records',
      {'status': status, 'error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setTime(int id, DateTime time) async {
    final row = await get(id);
    final data = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    data['at'] = time.toUtc().toIso8601String();
    await db.update(
      'records',
      {'payload': jsonEncode(data), 'status': 'pending', 'error': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> edit(int id, Map<String, dynamic> patch) => db.transaction((
    txn,
  ) async {
    final row = (await txn.query(
      'records',
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    final data = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    for (final key in [
      'title',
      'date',
      'phone',
      'amountMinor',
      'currency',
      'direction',
      'body',
      'fields',
      'template',
      'category',
    ]) {
      if (patch.containsKey(key)) data[key] = patch[key];
    }
    if (row['kind'] == 'phone' &&
        (!PhoneRecord.hasName(data['title']) ||
            !PhoneRecord.hasNumber(data['phone']))) {
      throw StateError('电话记录需要联系人姓名和电话号码，请补充完整');
    }
    final requiredMissing = RecordFields.missing(data);
    // Existing incomplete records stay editable, but an edit cannot erase a
    // required value that was previously present.
    final previous =
        jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    final previousMissing = RecordFields.missing(previous).toSet();
    final newlyMissing = requiredMissing
        .where((label) => !previousMissing.contains(label))
        .toList();
    if (newlyMissing.isNotEmpty) {
      throw StateError('必填项不能为空：${newlyMissing.join('、')}');
    }
    await txn.update(
      'records',
      {'payload': jsonEncode(data)},
      where: 'id = ?',
      whereArgs: [id],
    );
  });

  Future<void> link(int first, int second) => db.transaction((txn) async {
    final rows = await txn.query(
      'records',
      where: 'id IN (?, ?)',
      whereArgs: [first, second],
    );
    if (first == second || rows.length != 2) throw StateError('关联的历史记录不存在');
    for (final row in rows) {
      final data = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      final other = row['id'] == first ? second : first;
      data['relatedRecordIds'] = {
        ...List<int>.from(data['relatedRecordIds'] as List? ?? []),
        other,
      }.toList();
      await txn.update(
        'records',
        {'payload': jsonEncode(data)},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  });

  Future<void> delete(int id) => db.transaction((txn) async {
    await txn.delete('records', where: 'id = ?', whereArgs: [id]);
    for (final row in await txn.query('records')) {
      final data = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      final related = List<int>.from(data['relatedRecordIds'] as List? ?? []);
      if (related.remove(id)) {
        data['relatedRecordIds'] = related;
        await txn.update(
          'records',
          {'payload': jsonEncode(data)},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    }
  });
}
