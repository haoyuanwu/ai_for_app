import 'dart:convert';

import '../core/local_context.dart';
import '../core/local_store.dart';
import 'record_repository.dart';

/// Only uniquely located records from this request can be linked.
class RecordLinks {
  RecordLinks(this.store, this.request, {this.onSaved});
  final LocalStore store;
  final String request;
  final void Function(String)? onSaved;
  final _located = <int>{};
  static bool requested(String text) =>
      !RegExp(r'如果|假如|假设|不要|别|取消|是否|[？?]').hasMatch(text) &&
      RegExp(r'^(?:请)?关联|(?:把|将|给|帮我).{0,80}关联|关联到|关联至|建立关联').hasMatch(text);
  Future<String> page(String scope, String query, int offset) async {
    final result = await LocalContext(store).page(scope, query, offset);
    final data = jsonDecode(result) as Map<String, dynamic>;
    if (scope == 'records') {
      for (final item in data['items'] as List) {
        final id = item['id'];
        if (id is int &&
            (data['total'] == 1 ||
                RegExp('(?:记录|第|#)\\s*$id(?:条|\\b)').hasMatch(request))) {
          _located.add(id);
        }
      }
    }
    return result;
  }

  Future<String> link(int recordId, int relatedRecordId) async {
    if (!requested(request) ||
        !_located.contains(recordId) ||
        !_located.contains(relatedRecordId)) {
      return jsonEncode({
        'error': '先分别查询两条历史记录。多个候选须先让用户明确日期、名称或记录编号，不能猜选。未修改数据。',
      });
    }
    if (recordId == relatedRecordId) return jsonEncode({'error': '不能关联记录自身'});
    final repo = RecordRepository(store.database);
    await repo.link(recordId, relatedRecordId);
    final a =
        jsonDecode((await repo.get(recordId))['payload'] as String) as Map;
    final b = jsonDecode(
      (await repo.get(relatedRecordId))['payload'] as String,
    ) as Map;
    final receipt = '已关联“${a['title']}”和“${b['title']}”，已更新原记录。';
    onSaved?.call(receipt);
    return jsonEncode({
      'updated': true,
      'recordId': recordId,
      'relatedRecordId': relatedRecordId,
      'receipt': receipt,
    });
  }
}
