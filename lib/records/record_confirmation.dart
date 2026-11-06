import 'dart:convert';

import 'phone_record.dart';

import 'extracted_record.dart';
import 'reminder_time.dart';
import 'direct_record_intent.dart';
import 'record_templates.dart';
import 'record_fields.dart';

class RecordProposal {
  RecordProposal(this.id, this.sourceId, this.status, this.items, this.context);
  factory RecordProposal.fromRow(Map<String, Object?> row) => RecordProposal(
    row['id'] as int,
    row['source_id'] as String,
    row['status'] as String,
    List<Map<String, dynamic>>.from(
      (jsonDecode(row['payload'] as String) as List).map(
        (v) => Map<String, dynamic>.from(v as Map),
      ),
    ),
    row['context'] as String? ?? '',
  );
  final int id;
  final String sourceId, status, context;
  final List<Map<String, dynamic>> items;
  List<String> get missingFields => [
    for (final item in items) ...RecordFields.missing(item),
  ];
  Set<int> get duplicateRecordIds => {
    for (final item in items)
      for (final id in item['duplicateRecordIds'] as List? ?? []) id as int,
  };
  String get question {
    if (duplicateRecordIds.isNotEmpty) {
      final preview = items.map((v) => '• ${recordPreview(v)}').join('\n');
      return '发现已有相同交易时间或日期、相同金额的账单（记录编号：${duplicateRecordIds.join('、')}），可能是同一笔。'
          '仅有日期时按同日同金额提示可能重复。\n$preview\n\n'
          '${missingFields.isEmpty ? '仍要再记录一次吗？请再次确认记录，或选择不要记录。' : '请先补充：${missingFields.join('、')}，然后确认是否仍要记录。'}';
    }
    final incompletePhone = items
        .where((item) => item['kind'] == 'phone')
        .firstOrNull;
    if (incompletePhone != null && missingFields.isNotEmpty) {
      final missingName = !PhoneRecord.hasName(incompletePhone['title']);
      final missingPhone = !PhoneRecord.hasNumber(incompletePhone['phone']);
      if (missingName && missingPhone) return '这条电话记录还需要联系人姓名和电话号码，补充一下吧。';
      if (missingName) return '这是谁的电话？请告诉我联系人的姓名。';
      if (missingPhone) return '“${incompletePhone['title']}”的电话号码是多少？';
    }
    final preview = items.map((v) => '• ${recordPreview(v)}').join('\n');
    if (DirectRecordIntent.explicit(context) && missingFields.isNotEmpty) {
      return '还需要补充：${missingFields.join('、')}。补齐后我就帮你保存。\n$preview';
    }
    final asking = items.every((item) => item['kind'] == 'expense')
        ? '要帮你记账吗？'
        : '要帮你保存下来吗？';
    return '$preview\n\n${missingFields.isEmpty ? asking : '还需要补充：${missingFields.join('、')}。'}';
  }
}

String recordPreview(Map<String, dynamic> item) {
  final kind = RecordKind.values.byName(item['kind'] as String);
  final details = <String>[
    templateFor(item) == 'birthday' ? '生日' : kind.label,
    item['title'] as String,
  ];
  if (item['at'] != null) {
    details.add(
      DateTime.parse(item['at'] as String)
          .toLocal()
          .toString()
          .substring(0, 16),
    );
  } else if (item['date'] != null) {
    details.add(displayDate(item['date'] as String));
  } else if (item['birthdayMonthDay'] != null) {
    details.add('每年 ${item['birthdayMonthDay']}');
  } else if (item['birthdayText'] != null) {
    details.add(item['birthdayText'] as String);
  }
  if (kind == RecordKind.reminder && item['at'] == null) {
    details.add('时间待补充，确认后也不会启用通知');
  }
  if (kind == RecordKind.phone) {
    details.add(item['phone'] as String? ?? '号码待补充');
  }
  if (kind == RecordKind.expense) {
    details.add(
      '${item['direction'] == 'income'
          ? '收入'
          : item['direction'] == 'expense'
          ? '支出'
          : '收支待补充'} ${item['currency'] ?? '币种待补充'} ${item['amountMinor'] == null ? '金额待补充' : ((item['amountMinor'] as int) / 100).toStringAsFixed(2)}',
    );
  }
  for (final field in (item['fields'] as List? ?? [])) {
    details.add('${field['label']}：${field['value']}');
  }
  return details.join(' · ');
}

/// Consent is resolved from explicit user commands, never from model output.
class ConfirmationCommand {
  ConfirmationCommand(this.accept, {this.all = false, this.proposalId});
  final bool accept, all;
  final int? proposalId;
  static ConfirmationCommand? parse(String text) {
    final value = text.trim().replaceAll(RegExp(r'[\s，。！!、,.？?]'), '');
    if ([
      '同意',
      '同意记录',
      '确认',
      '确认记录',
      '记录吧',
      '记下来',
      '帮我记下来',
      '保存吧',
      '可以',
      '可以记录',
      '好',
      '好的',
      '是的',
      '是',
      '行',
      '没错',
      '保存',
      '记录',
      '记录下来',
      '确认保存',
    ].contains(value)) {
      return ConfirmationCommand(true);
    }
    if (RegExp(r'^(?:好|好的|可以|行|嗯)?(?:帮我)?(?:记录|保存|记下|记)(?:下来|一下|吧|这些|这条|这笔)*$')
        .hasMatch(value)) {
      return ConfirmationCommand(true);
    }
    if ([
      '不同意',
      '不要记录',
      '不记录',
      '不保存',
      '不用记录',
      '取消记录',
      '算了',
      '取消',
      '拒绝',
      '别记',
      '不用了',
    ].contains(value)) {
      return ConfirmationCommand(false);
    }
    if (['全部记录', '同意记录全部', '全部同意', '全部确认', '都记下来'].contains(value)) {
      return ConfirmationCommand(true, all: true);
    }
    if (['全部不记录', '全部拒绝', '全部取消'].contains(value)) {
      return ConfirmationCommand(false, all: true);
    }
    final batch = RegExp(r'^(确认|记录|同意|拒绝|取消|不记录)第([零一二两三四五六七八九十0-9]+)批$')
        .firstMatch(value);
    if (batch != null) {
      return ConfirmationCommand(
        ['确认', '记录', '同意'].contains(batch[1]),
        proposalId: chineseNumber(batch[2]!),
      );
    }
    return null;
  }

  List<RecordProposal> resolve(List<RecordProposal> pending) {
    if (all) return pending;
    if (proposalId != null) {
      return pending.where((p) => p.id == proposalId).toList();
    }
    return pending.length == 1 ? pending : [];
  }
}
