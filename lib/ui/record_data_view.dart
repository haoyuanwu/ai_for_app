import 'package:flutter/material.dart';

import '../records/extracted_record.dart';
import '../records/record_templates.dart';

/// Different record kinds keep different fields and visual emphasis.
class RecordDataView extends StatelessWidget {
  const RecordDataView({
    super.key,
    required this.data,
    this.hideChatSource = false,
    this.compact = false,
  });
  final Map<String, dynamic> data;
  final bool hideChatSource;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final data = presentRecord(this.data);
    final template = templateFor(data);
    final kind = RecordKind.values.byName(data['kind'] as String);
    final at = DateTime.tryParse(data['at'] as String? ?? '')?.toLocal();
    Widget detail(IconData icon, String text) => Padding(
      padding: EdgeInsets.only(top: compact ? 4 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(text)),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 4 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                switch (template) {
                  'birthday' => Icons.cake_outlined,
                  'expense' => Icons.account_balance_wallet_outlined,
                  'phone' => Icons.contact_phone_outlined,
                  'image' => Icons.image_outlined,
                  'audio' => Icons.graphic_eq,
                  'task' => Icons.checklist,
                  _ => Icons.event_note_outlined,
                },
                color: Theme.of(context).colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  compact
                      ? '${data['title']}'
                      : '${recordTemplates[template]} · ${data['title']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (template == 'birthday') ...[
            SizedBox(height: compact ? 6 : 12),
            Text(
              data['date'] != null
                  ? displayDate(data['date'] as String)
                  : data['birthdayText'] != null
                  ? data['birthdayText'] as String
                  : data['birthdayMonthDay'] != null
                  ? '每年 ${data['birthdayMonthDay']}'
                  : '生日日期待补充',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              data['birthdayText'] != null
                  ? '按农历保存，未换算为公历'
                  : data['date'] != null
                  ? '已记住这个重要的日子'
                  : data['birthdayMonthDay'] != null
                  ? '出生年份尚未提供'
                  : '补充日期后，将在这里清晰展示',
            ),
          ],
          if (template != 'birthday' &&
              kind == RecordKind.note &&
              data['date'] != null)
            detail(Icons.event_outlined, displayDate(data['date'] as String)),
          if (kind == RecordKind.expense) ...[
            Text(
              '${data['direction'] == 'income'
                  ? '收入'
                  : data['direction'] == 'expense'
                  ? '支出'
                  : '收支待补充'} ${data['currency'] ?? '币种待补充'} ${data['amountMinor'] == null ? '金额待补充' : ((data['amountMinor'] as int) / 100).toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (data['date'] != null)
              detail(Icons.event_outlined, displayDate(data['date'] as String)),
          ],
          if (template != 'birthday' &&
              (kind == RecordKind.reminder || kind == RecordKind.date))
            detail(
              kind == RecordKind.reminder
                  ? Icons.alarm_outlined
                  : Icons.event_outlined,
              at?.toString().substring(0, 16) ??
                  (data['date'] == null
                      ? null
                      : displayDate(data['date'] as String)) ??
                  '请在对话中补充日期${kind == RecordKind.reminder ? '和具体时刻' : ''}',
            ),
          if (kind == RecordKind.phone)
            detail(Icons.phone_outlined, data['phone'] as String? ?? '号码待补充'),
          if (kind == RecordKind.task)
            detail(
              Icons.check_box_outline_blank,
              '待办事项${data['date'] == null ? '' : ' · ${data['date']}'}',
            ),
          if ((data['category'] as String? ?? '').isNotEmpty)
            detail(Icons.sell_outlined, '分类：${data['category']}'),
          if ((data['body'] as String? ?? '').isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: compact ? 6 : 12),
              child: SelectableText(data['body'] as String),
            ),
          for (final field in data['fields'] as List? ?? [])
            if (!hideChatSource ||
                !(({
                      '聊天来源',
                      '聊天原文',
                      '原始聊天',
                      '聊天记录',
                      '原文',
                      '来源消息',
                    }.contains('${field['label']}')) ||
                    ('${field['label']}' == '来源' &&
                        '${field['value']}'.contains('聊天'))))
              Padding(
                padding: EdgeInsets.only(top: compact ? 4 : 8),
                child: SelectableText('${field['label']}：${field['value']}'),
              ),
        ],
      ),
    );
  }
}
