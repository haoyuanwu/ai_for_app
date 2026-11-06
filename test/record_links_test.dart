import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_links.dart';

void main() {
  late Directory root;
  late LocalStore store;
  late RecordRepository repo;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('record_links');
    store = await LocalStore.openAt(root);
    repo = RecordRepository(store.database);
    await repo.insert('original', [
      const ExtractedRecord(
        kind: RecordKind.task,
        title: '杭州旅行',
        quote: '杭州旅行',
      ),
      const ExtractedRecord(
        kind: RecordKind.expense,
        title: '车票',
        quote: '车票花了100元',
        amountMinor: 10000,
        currency: 'CNY',
        direction: 'expense',
      ),
    ]);
  });
  tearDown(() async {
    await store.database.close();
    await root.delete(recursive: true);
  });
  test('links require unique lookup and update original rows in both directions without inserting', () async {
    final rows = await repo.all();
    final a = rows.first['id'] as int;
    final b = rows.last['id'] as int;
    final session = RecordLinks(store, '把车票关联到杭州旅行');
    expect(jsonDecode(await session.link(a, b))['error'], isNotNull);
    await session.page('records', '', 0);
    expect(jsonDecode(await session.link(a, b))['error'], isNotNull);
    await session.page('records', '杭州旅行', 0);
    await session.page('records', '车票', 0);
    expect(jsonDecode(await session.link(a, b))['updated'], isTrue);
    await session.link(a, b);
    expect((await repo.all()).length, 2);
    for (final row in rows) {
      final current = await repo.get(row['id'] as int);
      expect(current['source_id'], row['source_id']);
      expect(current['status'], row['status']);
      final payload = jsonDecode(current['payload'] as String);
      expect(payload['relatedRecordIds'], [row['id'] == a ? b : a]);
    }
  });
  test(
    'questions cannot authorize edits and missing targets roll back',
    () async {
      final rows = await repo.all();
      final a = rows.first['id'] as int;
      final b = rows.last['id'] as int;
      final session = RecordLinks(store, '如何关联记录？');
      await session.page('records', '杭州旅行', 0);
      await session.page('records', '车票', 0);
      expect(jsonDecode(await session.link(a, b))['error'], isNotNull);
      await expectLater(repo.link(a, 999999), throwsStateError);
      expect((await repo.all()).length, 2);
      expect(
        jsonDecode(
          (await repo.get(a))['payload'] as String,
        )['relatedRecordIds'],
        isNull,
      );
    },
  );
}
