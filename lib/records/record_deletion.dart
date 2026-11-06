import 'dart:convert';

import '../core/local_context.dart';
import '../core/local_store.dart';
import 'record_service.dart';
import 'record_confirmation.dart';

class RecordDeletion {
  RecordDeletion(
    this.store,
    this.request,
    this.service, {
    this.onPreview,
    this.onFailed,
  });
  final LocalStore store;
  final String request;
  final RecordService service;
  final void Function(String)? onPreview, onFailed;
  final _located = <int>{};
  static bool requested(String text) =>
      !RegExp(r'如果|假如|假设|不要|别删|别清|是否|他说|你说|怎么|如何|[？?]').hasMatch(text) &&
      RegExp(r'删除|删掉|删去|清理|清空').hasMatch(text);
  Future<String> page(String scope, String query, int offset) async {
    final raw = await LocalContext(store).page(scope, query, offset);
    final data = jsonDecode(raw) as Map;
    if (scope == 'records' &&
        query.trim().isNotEmpty &&
        request.contains(query.trim())) {
      for (final item in data['items'] as List) {
        final id = item['id'];
        if (id is int &&
            (data['total'] == 1 ||
                RegExp('(?:记录|第|#)\\s*$id(?:条|\\b)').hasMatch(request))) {
          _located.add(id);
        }
      }
    }
    return raw;
  }

  Future<String> delete(int id) async {
    if (!requested(request) ||
        !_located.contains(id) ||
        RegExp(r'全部|所有|清空').hasMatch(request)) {
      return jsonEncode({
        'deleted': false,
        'error': '未删除。需先按用户描述查询并唯一定位单条历史记录；有多个候选先追问。',
      });
    }
    final current = store.data['pendingDeletion'] as Map?;
    if (current != null && current['id'] != id) {
      return jsonEncode({'deleted': false, 'error': '已有待确认删除，请先确认或取消上一条。'});
    }
    final row = await service.repository.get(id);
    final payload =
        jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    final question =
        '待删除记录 #$id：\n${recordPreview(payload)}\n确认删除吗？回复“确认删除第$id条”或“取消删除”。${row['kind'] == 'reminder' ? '对应提醒也会取消。' : ''}';
    final old = store.data['pendingDeletion'];
    store.data['pendingDeletion'] = {
      'id': id,
      'payload': row['payload'],
      'question': question,
      'token': DateTime.now().microsecondsSinceEpoch.toString(),
    };
    try {
      await store.save();
    } catch (_) {
      if (old == null) {
        store.data.remove('pendingDeletion');
      } else {
        store.data['pendingDeletion'] = old;
      }
      rethrow;
    }
    onPreview?.call(question);
    return jsonEncode({
      'deleted': false,
      'pendingConfirmation': true,
      'question': question,
    });
  }

  static Future<String?> respond(
    LocalStore store,
    RecordService service,
    String text,
  ) async {
    final pending = store.data['pendingDeletion'] as Map?;
    if (pending == null) return null;
    final command = text.trim().replaceAll(RegExp(r'[。！!\s]'), '');
    final id = pending['id'] as int;
    final cancel = ['取消删除', '不删除', '不要删除', '保留记录'].contains(command);
    final displayed = store.messages.any(
      (m) =>
          m['role'] == 'assistant' &&
          m['kind'] == 'deletion_proposal' &&
          m['deletionToken'] == pending['token'],
    );
    final explicit = RegExp('^确认删除(?:第|记录|#)?$id(?:条)?\$').hasMatch(command);
    final latest = store.messages
        .where((m) => m['role'] == 'assistant')
        .lastOrNull;
    final contextual =
        ['确认删除', '删除吧', '确认', '确定', '是', '是的', '好的', '好'].contains(command) &&
        latest?['kind'] == 'deletion_proposal' &&
        latest?['deletionToken'] == pending['token'];
    if (!cancel && (!displayed || (!explicit && !contextual))) return null;
    if (cancel) {
      store.data.remove('pendingDeletion');
      await store.save();
      return '已取消删除，记录仍保留。';
    }
    final rows = await service.repository.db.query(
      'records',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) {
      store.data.remove('pendingDeletion');
      await store.save();
      return '该记录已不存在，没有执行重复删除。';
    }
    if (rows.single['payload'] != pending['payload']) {
      store.data.remove('pendingDeletion');
      await store.save();
      return '记录内容已变化，请重新查找并确认后再删除。';
    }
    try {
      await service.delete(id, expectedPayload: pending['payload'] as String);
    } catch (e) {
      return '删除失败，记录仍保留：$e';
    }
    store.data.remove('pendingDeletion');
    await store.save();
    final title = (jsonDecode(pending['payload'] as String) as Map)['title'];
    return '已删除“$title”${rows.single['kind'] == 'reminder' ? '，对应提醒已取消' : ''}。';
  }
}
