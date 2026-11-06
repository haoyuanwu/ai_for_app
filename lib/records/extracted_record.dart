import 'dart:convert';

import 'reminder_time.dart';
import 'record_templates.dart';

enum RecordKind { date, reminder, phone, task, expense, note }

extension RecordKindLabel on RecordKind {
  String get label => ['日期', '提醒', '电话', '事项', '记账', '笔记'][index];
}

/// A validated extraction proposal, still traceable to a literal user quote.
class ExtractedRecord {
  const ExtractedRecord({
    required this.kind,
    required this.title,
    required this.quote,
    this.at,
    this.date,
    this.category,
    this.fields = const [],
    this.template,
    this.body,
    this.phone,
    this.amountMinor,
    this.currency,
    this.direction,
  });
  final String? template, body;
  final RecordKind kind;
  final String title, quote;
  final DateTime? at;
  final String? phone, currency, direction, date;
  final int? amountMinor;
  final String? category;
  final List<Map<String, String>> fields;
  Map<String, dynamic> toJson() => presentRecord({
    'template': template,
    'body': body,
    'kind': kind.name,
    'title': title,
    'quote': quote,
    'at': at?.toUtc().toIso8601String(),
    'date': date,
    'category': category,
    'fields': fields,
    'phone': phone,
    'amountMinor': amountMinor,
    'currency': currency,
    'direction': direction,
  });

  static List<ExtractedRecord> parse(
    String response,
    String source, {
    DateTime? reference,
  }) {
    var raw = response.trim();
    // Some local models emit reasoning/fences despite the JSON-only instruction.
    if (raw.contains('</think>')) raw = raw.split('</think>').last.trim();
    raw = raw
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
    final value = jsonDecode(raw);
    if (value is! Map || value['records'] is! List) {
      throw const FormatException('模型未返回有效记录 JSON');
    }
    final list = value['records'] as List;
    if (list.length > 30) throw const FormatException('单条消息最多提取 30 条记录');
    final records = <ExtractedRecord>[];
    final seen = <String>{};
    for (final item in list) {
      if (item is! Map) throw const FormatException('记录格式无效');
      final kind = RecordKind.values
          .where((k) => k.name == item['kind'])
          .firstOrNull;
      var title = item['title'];
      final quote = item['quote'];
      if (kind == null ||
          title is! String ||
          title.trim().isEmpty ||
          title.length > 200 ||
          quote is! String ||
          quote.trim().isEmpty ||
          !source.contains(quote)) {
        throw const FormatException('提取结果缺少有效类型、标题或用户原文依据');
      }
      if (kind == RecordKind.phone && !source.contains(title)) {
        title = '姓名待补充';
      }
      if (kind == RecordKind.reminder &&
          RegExp(r'(不要|不用|无需|取消|不必).{0,6}(提醒|通知|闹钟)').hasMatch(quote)) {
        continue;
      }
      if (kind == RecordKind.expense &&
          RegExp(r'如果|假如|假设|预算|多少钱|计划花|准备花').hasMatch(quote)) {
        continue;
      }
      var dateOnly = item['date'];
      if (quote.contains('生日') || item['template'] == 'birthday') {
        dateOnly = presentRecord({
          'kind': 'date',
          'template': 'birthday',
          'quote': quote,
          'date': null,
        })['date'];
      }
      if (dateOnly != null) {
        if (dateOnly is! String ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(dateOnly)) {
          throw const FormatException('日期需为 YYYY-MM-DD');
        }
        final parsed = DateTime.tryParse(dateOnly);
        if (parsed == null ||
            parsed.toIso8601String().substring(0, 10) != dateOnly) {
          throw const FormatException('日期无效');
        }
      }
      DateTime? at;
      final datetime = item['datetime'];
      if (datetime != null) {
        if (datetime is! String ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$')
                .hasMatch(datetime)) {
          throw const FormatException('时间需为含时区的 ISO 8601');
        }
        at = DateTime.tryParse(datetime);
        if (at == null || at.year < 2000 || at.year > 2200) {
          throw const FormatException('日期无效');
        }
        // DateTime.parse normalizes e.g. February 30; reject that rather than scheduling it.
        final date = datetime
            .substring(0, 10)
            .split('-')
            .map(int.parse)
            .toList();
        if (date[1] < 1 ||
            date[1] > 12 ||
            date[2] < 1 ||
            DateTime.utc(date[0], date[1], date[2]).day != date[2] ||
            int.parse(datetime.substring(11, 13)) > 23 ||
            int.parse(datetime.substring(14, 16)) > 59 ||
            int.parse(datetime.substring(17, 19)) > 59) {
          throw const FormatException('日期或时钟无效');
        }
      }
      if (kind == RecordKind.reminder) {
        final timeQuote = item['timeQuote'];
        at = resolveReminderTime(
          timeQuote is String &&
                  timeQuote.isNotEmpty &&
                  quote.contains(timeQuote)
              ? timeQuote
              : quote,
          reference ?? DateTime.now(),
        );
        if (!RegExp(r'提醒|叫我|通知我|闹钟|别忘|不要忘').hasMatch(quote)) {
          throw const FormatException('提醒缺少用户意图依据');
        }
      }
      String? phone;
      if (kind == RecordKind.phone) {
        phone = item['phone'] is String ? item['phone'] as String : null;
        final digits = (phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
        if (phone != null &&
            (digits.length < 5 ||
                digits.length > 18 ||
                !quote.replaceAll(RegExp(r'[^0-9+]'), '').contains(digits))) {
          throw const FormatException('电话号码不在用户原文中');
        }
      }
      int? amount;
      String? currency, direction;
      if (kind == RecordKind.expense) {
        final money = item['amount'];
        if (money != null) {
          if (money is! String ||
              !RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(money)) {
            throw const FormatException('金额格式无效');
          }
          final parts = money.split('.');
          amount =
              int.parse(parts[0]) * 100 +
              int.parse((parts.length == 1 ? '0' : parts[1]).padRight(2, '0'));
          final literal =
              RegExp(r'(?<![0-9.])[0-9]+(?:\.[0-9]{1,2})?(?![0-9.])')
                  .allMatches(quote)
                  .any((m) => num.tryParse(m[0]!) == num.tryParse(money));
          if (!literal) {
            amount =
                null; // Unsupported written-number amounts stay incomplete.
          }
          if (amount != null && amount <= 0) {
            throw const FormatException('金额必须大于零');
          }
        }
        currency = item['currency'] as String?;
        direction = item['direction'] as String?;
        if (currency != null &&
            !['CNY', 'USD', 'EUR', 'HKD', 'JPY', 'GBP'].contains(currency)) {
          throw const FormatException('暂不支持该币种');
        }
        if (direction != null && !['income', 'expense'].contains(direction)) {
          throw const FormatException('收支类型无效');
        }
      }
      final fields = <Map<String, String>>[];
      final rawFields = item['fields'] ?? [];
      if (rawFields is! List || rawFields.length > 24) {
        throw const FormatException('扩展字段无效');
      }
      for (final field in rawFields) {
        if (field is! Map ||
            field['label'] is! String ||
            field['value'] is! String ||
            (field['label'] as String).isEmpty ||
            (field['label'] as String).length > 30 ||
            (field['value'] as String).isEmpty ||
            (field['value'] as String).length > 300 ||
            !quote.contains(field['value'] as String)) {
          throw const FormatException('扩展字段缺少用户原文依据');
        }
        fields.add({
          'label': field['label'] as String,
          'value': field['value'] as String,
        });
      }
      final category = item['category'] as String?;
      if (category != null && category.length > 30) {
        throw const FormatException('分类名称过长');
      }
      final record = ExtractedRecord(
        body: item['body'] is String ? item['body'] as String : null,
        template:
            item['template'] is String &&
                recordTemplates.containsKey(item['template'])
            ? item['template'] as String
            : null,
        kind: kind,
        title: title.trim(),
        quote: quote,
        at: at,
        date: dateOnly as String?,
        category: category,
        fields: fields,
        phone: phone,
        amountMinor: amount,
        currency: currency,
        direction: direction,
      );
      if (seen.add(jsonEncode(record.toJson()))) records.add(record);
    }
    return records;
  }
}

/// Constrain syntax during generation; semantic evidence is still checked above.
final recordExtractionSchema = <String, dynamic>{
  'type': 'object',
  'additionalProperties': false,
  'required': ['records'],
  'properties': {
    'records': {
      'type': 'array',
      'maxItems': 30,
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': [
          'kind',
          'title',
          'quote',
          'date',
          'datetime',
          'timeQuote',
          'phone',
          'amount',
          'currency',
          'direction',
          'category',
          'body',
          'template',
          'fields',
        ],
        'properties': {
          'kind': {
            'type': 'string',
            'enum': ['date', 'reminder', 'phone', 'task', 'expense', 'note'],
          },
          'title': {'type': 'string', 'minLength': 1, 'maxLength': 200},
          'quote': {'type': 'string', 'minLength': 1},
          for (final field in [
            'date',
            'datetime',
            'timeQuote',
            'phone',
            'amount',
            'currency',
            'direction',
            'category',
          ])
            field: {
              'type': ['string', 'null'],
            },
          'body': {
            'type': ['string', 'null'],
            'maxLength': 2000,
          },
          'template': {'type': 'string', 'enum': recordTemplates.keys.toList()},
          'fields': {
            'type': 'array',
            'maxItems': 24,
            'items': {
              'type': 'object',
              'required': ['label', 'value'],
              'additionalProperties': false,
              'properties': {
                'label': {'type': 'string', 'maxLength': 30},
                'value': {'type': 'string', 'maxLength': 300},
              },
            },
          },
        },
      },
    },
  },
};
