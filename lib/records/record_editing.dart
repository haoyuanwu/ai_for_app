import 'dart:convert';

import '../core/local_context.dart';
import '../core/local_store.dart';
import 'record_service.dart';
import 'record_templates.dart';
import 'record_confirmation.dart';
import 'reminder_time.dart';

class RecordEditing {
  RecordEditing(this.store, this.request, this.service, {this.onSaved});
  final LocalStore store;
  final String request;
  final RecordService service;
  final void Function(String)? onSaved;
  final located = <int>{};
  static bool requested(String text) =>
      !RegExp(r'如果|假如|假设|不要|别改|如何|怎么|[？?]').hasMatch(text) &&
      RegExp(r'修改|改成|改为|改到|更新|更正|改一下').hasMatch(text);
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
          located.add(id);
        }
      }
    }
    return raw;
  }

  Future<String> edit(int id, String field, String value) async {
    if (!requested(request) || !located.contains(id)) {
      return jsonEncode({
        'updated': false,
        'error': '请先按用户描述唯一查找目标记录；有多个候选先追问。',
      });
    }
    final row = await service.repository.get(id);
    final data = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    final patch = <String, dynamic>{};
    bool literal(String s) => s.isNotEmpty && request.contains(s);
    switch (field) {
      case 'title':
      case 'body':
      case 'phone':
        if (!literal(value) || value.length > (field == 'title' ? 200 : 2000)) {
          throw const FormatException('修改值必须来自用户原话');
        }
        if (field == 'phone' &&
            (data['kind'] != 'phone' ||
                !RegExp(r'^\+?[0-9 ()-]{5,25}$').hasMatch(value))) {
          throw const FormatException('号码无效');
        }
        patch[field] = value;
      case 'date':
        if (data['kind'] == 'reminder') {
          throw const FormatException('提醒请修改完整时刻');
        }
        final date = DateTime.tryParse(value);
        final parts = value.split('-');
        if (date == null ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
            !date.toIso8601String().startsWith(value) ||
            !(request.contains(value) ||
                request.contains(
                  '${int.parse(parts[0])}年${int.parse(parts[1])}月${int.parse(parts[2])}',
                ))) {
          throw const FormatException('日期必须由用户明确提供年月日');
        }
        patch['date'] = value;
      case 'amount':
        if (data['kind'] != 'expense' ||
            !RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(value) ||
            !RegExp(r'\d+(?:\.\d{1,2})?')
                .allMatches(request)
                .any((m) => num.tryParse(m[0]!) == num.tryParse(value)) ||
            (num.tryParse(value) ?? 0) <= 0) {
          throw const FormatException('金额必须来自用户明确的数值');
        }
        final parts = value.split('.');
        patch['amountMinor'] =
            int.parse(parts[0]) * 100 +
            int.parse((parts.length == 1 ? '0' : parts[1]).padRight(2, '0'));
      case 'at':
        if (data['kind'] != 'reminder') {
          throw const FormatException('只有提醒可修改通知时刻');
        }
        final at = resolveReminderTime(request, DateTime.now());
        if (at == null || !at.isAfter(DateTime.now())) {
          throw const FormatException('请提供明确的未来提醒日期和时刻');
        }
        await service.changeTime(id, at);
        final receipt =
            '已更新原提醒 #$id：${recordPreview({...data, 'at': at.toUtc().toIso8601String()})}。';
        onSaved?.call(receipt);
        return jsonEncode({'updated': true, 'id': id, 'receipt': receipt});
      case 'currency':
        if (data['kind'] != 'expense' ||
            !['CNY', 'USD', 'EUR', 'HKD', 'JPY', 'GBP'].contains(value) ||
            !request.contains(value)) {
          throw const FormatException('请明确指定币种代码');
        }
        patch['currency'] = value;
      case 'direction':
        if (data['kind'] != 'expense' ||
            !['income', 'expense'].contains(value) ||
            !request.contains(value == 'income' ? '收入' : '支出')) {
          throw const FormatException('请明确收入或支出');
        }
        patch['direction'] = value;
      case 'template':
        if (!recordTemplates.containsKey(value) ||
            !(request.contains(value) ||
                request.contains(
                  recordTemplates[value]!.replaceAll('卡片', ''),
                ))) {
          throw const FormatException('请明确指定展示模板');
        }
        patch['template'] = value;
      default:
        throw const FormatException('暂不支持此字段，请使用记录页编辑');
    }
    await service.edit(id, patch);
    final receipt = '已更新原记录 #$id：${recordPreview({...data, ...patch})}。';
    onSaved?.call(receipt);
    return jsonEncode({'updated': true, 'id': id, 'receipt': receipt});
  }
}
