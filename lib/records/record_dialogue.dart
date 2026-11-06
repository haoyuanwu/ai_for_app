import 'dart:convert';

import '../core/local_store.dart';
import 'record_confirmation.dart';
import 'record_deletion.dart';
import 'record_editing.dart';
import 'record_links.dart';
import 'record_service.dart';
import 'record_templates.dart';

/// Deterministic routing for explicit, uniquely named local records. Complex
/// requests may still use model tools, but a small model need not call tools for
/// the common query/edit/link/delete path.
class RecordDialogue {
  RecordDialogue(this.store, this.service);
  final LocalStore store;
  final RecordService service;

  /// Resolve a short answer only against the latest matching question.
  String? followup(String text) {
    final pending = store.data['recordInteraction'] as Map?;
    if (pending == null) return null;
    final latest = store.messages
        .where((m) => m['role'] == 'assistant')
        .lastOrNull;
    if (latest?['interactionToken'] != pending['token']) return null;
    final command = text.trim().replaceAll(RegExp(r'[。！!\s]'), '');
    if (['取消', '取消操作', '算了', '不用了'].contains(command)) return '__cancel__';
    if (['好', '好的', '确认', '确定', '是', '是的'].contains(command)) {
      return pending['mode'] == 'edit_value'
          ? '__need_value__'
          : '__need_choice__';
    }
    final ids = List<int>.from(pending['ids'] as List? ?? []);
    final explicit = RegExp(r'^(?:选择(?:记录)?|记录)?#(\d+)$').firstMatch(command);
    int? id;
    if (explicit != null) {
      id = int.tryParse(explicit[1]!);
    } else {
      final match = RegExp(r'^(?:第)?([0-9]+|一|二|三|四|五|六|七|八|九|十)(?:条|个)?$')
          .firstMatch(command);
      if (match != null) {
        const chinese = {
          '一': 1,
          '二': 2,
          '三': 3,
          '四': 4,
          '五': 5,
          '六': 6,
          '七': 7,
          '八': 8,
          '九': 9,
          '十': 10,
        };
        final n = int.tryParse(match[1]!) ?? chinese[match[1]];
        if (n != null && n > 0 && n <= ids.length) id = ids[n - 1];
      }
    }
    if (id != null && ids.contains(id)) {
      if (pending['operation'] == 'link') {
        final selected = List<int>.from(pending['selectedIds'] as List? ?? []);
        if (selected.isEmpty) {
          pending['selectedIds'] = [id];
          return '__link_pick__';
        }
        if (selected.first == id) return '__link_pick__';
        return '${pending['request']}（选择记录 #${selected.first} 和 #$id）';
      }
      return '${pending['request']}（选择记录 #$id）';
    }
    if (pending['mode'] == 'edit_value' &&
        command.isNotEmpty &&
        !RegExp(r'^(你好|谢谢|查询|查一下|取消删除)').hasMatch(command)) {
      final update = RegExp(r'改为|改成|更正为').hasMatch(text)
          ? text
          : '${pending['fieldLabel'] ?? ''}改为$text';
      return '${pending['request']}（选择记录 #${pending['targetId']}），$update';
    }
    if (pending['mode'] == 'missing_target' &&
        command.isNotEmpty &&
        !RegExp(r'查询|查一下|修改|改为|改成|删除|你好|谢谢').hasMatch(command)) {
      return '${pending['request']}，目标记录：$text';
    }
    return null;
  }

  Future<String?> handle(String text, {String? continuation}) async {
    final answer = continuation ?? followup(text);
    if (answer == '__need_choice__') {
      return '请先点击需要操作的记录，或回复“第一条”“第二条”，我不会替你选择。';
    }
    if (answer == '__need_value__') return '请直接提供新的具体内容，也可以取消修改。';
    if (answer == '__link_pick__') {
      await store.save();
      return '已选择第一条记录，请再选择另一条进行关联，也可以取消。';
    }
    if (answer == '__cancel__') {
      store.data.remove('recordInteraction');
      await store.save();
      return '已取消本次操作，记录未改变。';
    }
    if (answer != null) text = answer;

    final deleting = RecordDeletion.requested(text);
    final linking = RecordLinks.requested(text);
    final editing = !deleting && !linking && RecordEditing.requested(text);
    final querying = RegExp(
      r'查(?:一下|询|找|看)?|搜索|有哪些记录|我的.{0,30}(?:多少|哪天|几号|号码|生日|记录)|(?:记录|生日).{0,15}(?:多少|哪天|几号|是什么)|(?:花了|花费|支出|收入).{0,10}(?:多少|几)|(?:电话|号码).{0,6}(?:多少|是什么)',
    ).hasMatch(text);
    if (!deleting && !linking && !editing && !querying) return null;
    if (answer == null) store.data.remove('recordInteraction');
    final rows = await service.repository.all();
    final explicitIds = RegExp(r'(?:记录\s*#?|第|#)\s*(\d+)(?:条)?')
        .allMatches(text)
        .map((m) => int.parse(m[1]!))
        .toSet();
    List<Map<String, Object?>> match(String fragment) {
      final candidates = rows.where((row) {
        final data =
            jsonDecode(row['payload'] as String) as Map<String, dynamic>;
        final title = (data['title'] as String? ?? '').trim();
        if (explicitIds.isNotEmpty && (!linking || explicitIds.length == 2)) {
          return explicitIds.contains(row['id']);
        }
        return explicitIds.contains(row['id']) ||
            (title.isNotEmpty && fragment.contains(title));
      }).toList();
      // A full title is stronger than one title that is only its prefix.
      return candidates.where((row) {
        final title =
            (jsonDecode(row['payload'] as String) as Map)['title'] as String;
        return !candidates.any((other) {
          final otherTitle =
              (jsonDecode(other['payload'] as String) as Map)['title']
                  as String;
          return otherTitle != title &&
              otherTitle.contains(title) &&
              !fragment.replaceAll(otherTitle, '').contains(title);
        });
      }).toList();
    }

    final candidates = match(text);
    String summary(Map<String, Object?> row) =>
        '#${row['id']} · ${recordPreview(presentRecord(jsonDecode(row['payload'] as String) as Map<String, dynamic>))}';
    String choose() {
      if (!deleting && !editing && !linking) return '请补充记录名称、日期或编号。';
      store.data['recordInteraction'] = {
        'request': text,
        'token': DateTime.now().microsecondsSinceEpoch.toString(),
        'mode': candidates.isEmpty ? 'missing_target' : 'select_record',
        'operation': linking
            ? 'link'
            : editing
            ? 'edit'
            : 'delete',
        'ids': [for (final row in candidates.take(10)) row['id']],
        'options': [
          for (final row in candidates.take(10))
            {'id': row['id'], 'label': summary(row)},
        ],
      };
      return candidates.isEmpty
          ? '没有找到目标记录。请直接回复记录名称或编号，也可以取消。'
          : '找到多条记录（${candidates.length} 条），请点击选项，或回复“第一条”“第二条”。';
    }

    if (candidates.length == 1 && (deleting || editing)) {
      store.data.remove('recordInteraction');
    }
    Future<void> locate(dynamic session, Map<String, Object?> row) async {
      final title =
          (jsonDecode(row['payload'] as String) as Map)['title'] as String;
      if (explicitIds.contains(row['id'])) {
        await session.page('records', '${row['id']}', 0);
      } else {
        await session.page('records', title, 0);
      }
    }

    if (linking) {
      if (candidates.length != 2) {
        final result = choose();
        await store.save();
        return result;
      }
      store.data.remove('recordInteraction');
      final receipts = <String>[];
      final session = RecordLinks(store, text, onSaved: receipts.add);
      for (final row in candidates) {
        await locate(session, row);
      }
      final result = jsonDecode(
        await session.link(
          candidates[0]['id'] as int,
          candidates[1]['id'] as int,
        ),
      ) as Map;
      return receipts.isNotEmpty ? receipts.last : result['error'] as String?;
    }
    if (deleting) {
      if (candidates.length != 1) {
        final result = choose();
        await store.save();
        return result;
      }
      final session = RecordDeletion(store, text, service);
      await locate(session, candidates.single);
      final result = jsonDecode(
        await session.delete(candidates.single['id'] as int),
      ) as Map;
      return result['question'] as String? ?? result['error'] as String?;
    }
    if (editing) {
      if (candidates.length != 1) {
        final result = choose();
        await store.save();
        return result;
      }
      final row = candidates.single;
      final data = jsonDecode(row['payload'] as String) as Map;
      String? field, value;
      final date = RegExp(r'(\d{4})[年/.-](\d{1,2})[月/.-](\d{1,2})日?')
          .allMatches(text)
          .lastOrNull;
      final amount =
          RegExp(r'金额(?:改成|改为|更正为)\s*(\d+(?:\.\d{1,2})?)(?:元|块)?')
              .firstMatch(text) ??
          RegExp(
            r'(?:金额.{0,5}(?:改成|改为|更正为)|改成|改为|更正为)\s*(\d+(?:\.\d{1,2})?)\s*(?:元|块)',
          ).firstMatch(text);
      if (data['kind'] == 'reminder' &&
          RegExp(r'时间|时刻|提醒|点|明天|后天').hasMatch(text)) {
        field = 'at';
        value = text;
      } else if (date != null && RegExp(r'日期|生日|改成|改为|更正').hasMatch(text)) {
        field = 'date';
        value =
            '${date[1]}-${date[2]!.padLeft(2, '0')}-${date[3]!.padLeft(2, '0')}';
      } else if (amount != null && data['kind'] == 'expense') {
        field = 'amount';
        value = amount[1];
      } else {
        for (final (key, pattern) in [
          ('phone', r'(?:电话|号码).{0,5}(?:改成|改为|更正为)\s*(\+?[0-9 -]{5,25})'),
          ('title', r'(?:标题|名称|名字)(?:改成|改为|更正为)\s*(.+)'),
          ('body', r'(?:备注|正文)(?:改成|改为|更正为)\s*(.+)'),
        ]) {
          final m = RegExp(pattern).firstMatch(text);
          if (m != null) {
            field = key;
            value = m[1]!.trim().replaceFirst(RegExp(r'[。！!]$'), '');
            break;
          }
        }
        for (final template in recordTemplates.entries) {
          if (text.contains(template.value)) {
            field = 'template';
            value = template.key;
          }
        }
      }
      if (field == null || value == null) {
        final labels = ['金额', '标题', '名称', '备注', '正文', '日期', '生日', '电话', '号码'];
        final label = labels.where(text.contains).firstOrNull;
        store.data['recordInteraction'] = {
          'request': text,
          'token': DateTime.now().microsecondsSinceEpoch.toString(),
          'mode': 'edit_value',
          'targetId': row['id'],
          'fieldLabel': label,
          'ids': <int>[],
          'options': <Map<String, dynamic>>[],
        };
        await store.save();
        return label == null
            ? '已找到记录 #${row['id']}。请直接回复要修改的字段和新内容，例如“金额改为25元”或“标题改为周末午餐”。'
            : '已找到记录 #${row['id']}。请直接回复新的$label。';
      }
      final receipts = <String>[];
      final session = RecordEditing(
        store,
        text,
        service,
        onSaved: receipts.add,
      );
      await locate(session, row);
      try {
        final result = jsonDecode(
          await session.edit(row['id'] as int, field, value),
        ) as Map;
        return receipts.isNotEmpty ? receipts.last : result['error'] as String?;
      } catch (e) {
        return '尚未修改记录：$e';
      }
    }
    if (candidates.isNotEmpty) {
      return '找到以下记录：\n${candidates.take(10).map(summary).join('\n')}${candidates.length > 10 ? '\n请补充名称以缩小范围。' : ''}';
    }
    if (RegExp(r'(?:所有|全部|我的)记录|记录有哪些').hasMatch(text)) {
      return rows.isEmpty
          ? '暂无已保存记录。'
          : '已保存 ${rows.length} 条记录：\n${rows.take(10).map(summary).join('\n')}';
    }
    return null;
  }
}
