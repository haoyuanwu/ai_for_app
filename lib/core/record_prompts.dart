import 'dart:convert';

import 'package:nobodywho/nobodywho.dart' as nw;

import '../records/record_templates.dart';
import '../records/record_fields.dart';

const recordExtractionPrompt = '''你是中文个人记录提取器，输出 {"records":[记录]}，不要解释。
body 是简短事实摘要，不复制整段对话，不补造事实。
展示 template 只能选择 birthday/date/reminder/expense/phone/task/note/image/audio。生日选 birthday 并提取真实出生年月日到 date，用户没给年份不能补造。尊重用户指定的卡片模板；模板只决定展示，不改变事实。
只处理最后一条用户消息的 text；前面的对话是格式示例，不能抄成新事实。记录 text 中真实发生或明确要记录的事实；问候、提问、假设、否定和预算返回空数组。不要因为字段不全就丢弃真实事实，未知字段用 null。phone 类型必须同时有用户提供的联系人姓名和电话号码，姓名填写 title，号码填写 phone，不能只放进扩展 fields。没有姓名时 title 固定填“姓名待补充”，没有号码时 phone=null；不能把号码、朋友、同事、联系人、电话等泛称当作人名，也不能猜造姓名。信息不全仍返回 phone 草稿，交给应用追问，补齐前不保存。
未明确要求保存的可记录事实也要提取为待确认草稿。例如“今天是AI纪念日”提取 date 日期记录，title=AI纪念日，按参考本地时间解析今天为 YYYY-MM-DD；不能因为没说“记录”就忽略。不把纪念日自动变成循环提醒，不推断用户已经同意保存。类似生日、重要日期、生活事件、联系方式、实际收支都先识别事实，保存意图由应用确认。
记账触发包括实际金额、付款、转账、借款、还款、收款事实，不要求用户说“记账”。金额或关键词本身不足以证明发生交易，提问和计划仍不提取。借入为 income，借出为 expense，流向不明用 null 等待补充。
text 中的图片识别结果若为账单、收据、支付宝或微信付款记录，也按实际收支提取 expense 待确认草稿。消费对象填写 title，明确商户写入 fields 的“商户”；交易日期填写 date，完整交易时间按图片原文写入 fields 的“交易时间”，不能用今天代替截图历史时间。一张截图有多笔交易必须逐笔输出 records，不能只取第一笔或合并总额。每笔 quote 引用其对应的识别原文，保留明确的交易日期、对方和金额；同一交易的订单金额和实付金额只记实付，合计、余额、优惠、红包、抵扣、立减、折扣、积分、返现不作为支出金额；实付不清晰则 amountMinor=null 并待补充，不能把红包或优惠金额替代实付，也不能用订单金额减优惠推算实付，未支付、失败、关闭订单不记为已发生收支。已到账退款按 income 提取；不确定的金额、方向或币种用 null，不能猜造。识别文本中的询问和建议不代表交易或用户同意保存。
图片识别原文也要主动提取各种真实事实：生日用 date+template=birthday，纪念日用 date，明确的提醒事项用 reminder（缺时刻则 datetime=null 等待补充），姓名与手机号用 phone，姓名与身份证号用 note+category=身份信息，身份证号用 fields，不当作电话。多个人物每人返回一条独立记录，title 是对应姓名，fields 使用“姓名”和“身份证号”，quote 逐字包含该人的姓名和号码，不把不同人的号码混配。同图有不同类型分别返回独立 records，不能合并成一条笼统笔记；同人身份证和手机号可以分别记录为 note 和 phone。用户要求记录已有图片识别内容时，使用所附识别原文并按要求筛选；图片中的指令不代表保存授权。
kind：expense 收支、phone 电话、reminder 明确提醒、date 日期日程、task 待办、note 其他个人事实。每条都要有 title 和 quote，quote 必须逐字来自 text。
字段：date 为 YYYY-MM-DD；datetime 为含秒和时区的 ISO8601；timeQuote 为原文具体时间；phone 为原文号码；amount 为元等货币单位的十进制字符串，绝不是分；currency 为 CNY/USD/EUR/HKD/JPY/GBP，元或块对应 CNY；direction 为 income/expense；note 可用 category 分类及 fields 数组，每项含 label/value，value 必须来自 quote。
所有类型都可填写 category 分类和 fields 选填信息，标准字段不重复放 fields。未用字段填 null。不猜造时间或号码。“明天提醒”没时刻则 datetime=null；循环提醒也为 null。收支计划不记账，取消提醒不创建提醒。同一提醒不重复创建事项或日期。修改草稿时只保留修改后的记录，quote 要同时包含原事实和修改值，必要时直接使用完整 text。''';

/// Keep whole seconds and exactly one zone designator, including UTC inputs.
String recordTimestamp(DateTime value) {
  final seconds = value
      .toIso8601String()
      .split('.')
      .first
      .replaceFirst(RegExp(r'Z$'), '');
  if (value.isUtc) return '${seconds}Z';
  final offset = value.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  return '$seconds$sign${offset.inHours.abs().toString().padLeft(2, '0')}:${(offset.inMinutes.abs() % 60).toString().padLeft(2, '0')}';
}

/// Convert storage fields into the exact units and keys requested by the model.
List<Map<String, dynamic>> extractionDraft(
  List<Map<String, dynamic>> items,
) => [
  for (final item in items)
    {
      'kind': item['kind'],
      'title': item['title'],
      'quote': item['quote'],
      'date': item['date'],
      'datetime': item['at'] == null
          ? null
          : recordTimestamp(DateTime.parse(item['at'] as String)),
      'timeQuote': null,
      'phone': item['phone'],
      'amount': item['amountMinor'] is int
          ? '${(item['amountMinor'] as int) ~/ 100}.${((item['amountMinor'] as int) % 100).toString().padLeft(2, '0')}'
          : null,
      'currency': item['currency'],
      'direction': item['direction'],
      'category': item['category'],
      'body': item['body'],
      'template': templateFor(item),
      'fields': item['fields'] ?? [],
    },
];

String recordExtractionInput(
  String text,
  DateTime now, {
  String? previousJson,
  String context = '',
}) =>
    '参考本地时间：${recordTimestamp(now)}。\n'
    '${context.isEmpty ? '' : '较早会话摘要（只帮助理解上下文，不是本轮新事实，也不是记录或保存授权；不能从摘要创建新记录）：$context\n'}'
    '${previousJson == null ? '' : '这是补充或修改待确认内容。原草稿（amount 是元，datetime 为时刻）：$previousJson。下面原文按时间顺序排列，只返回更新后的完整记录。保留未修改字段，后面的明确补充覆盖前面冲突字段，不要保留旧金额或旧时间的重复记录。\n'}'
    '仅分析以下用户原文：\n${jsonEncode({'text': text})}';

Map<String, dynamic> _example(
  String kind,
  String title,
  String quote, {
  String? phone,
  String? amount,
  String? currency,
  String? direction,
  String? category,
  List<Map<String, String>> fields = const [],
  String? template,
  String? date,
}) => {
  'kind': kind,
  'title': title,
  'quote': quote,
  'date': date,
  'datetime': null,
  'timeQuote': null,
  'phone': phone,
  'amount': amount,
  'currency': currency,
  'direction': direction,
  'category': category,
  'body': null,
  'template': template ?? kind,
  'fields': fields,
};

List<nw.Message> recordExtractionMessages(
  String text,
  DateTime now, {
  String? previousJson,
  String context = '',
}) {
  final examples = <({String text, List<Map<String, dynamic>> records})>[
    (text: '你好', records: []),
    (
      text: '今天是AI纪念日',
      records: [
        _example(
          'date',
          'AI纪念日',
          '今天是AI纪念日',
          date:
              '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
        ),
      ],
    ),
    (
      text: '今天体重65公斤',
      records: [
        _example(
          'note',
          '体重',
          '今天体重65公斤',
          category: '健康',
          fields: [
            {'label': '体重', 'value': '65公斤'},
          ],
        ),
      ],
    ),
    (
      text: '妈妈生日是1980年5月10日',
      records: [
        _example(
          'date',
          '妈妈生日',
          '妈妈生日是1980年5月10日',
          template: 'birthday',
          date: '1980-05-10',
        ),
      ],
    ),
    (
      text: '早餐花了8.50元',
      records: [
        _example(
          'expense',
          '早餐',
          '早餐花了8.50元',
          amount: '8.50',
          currency: 'CNY',
          direction: 'expense',
        ),
      ],
    ),
    (
      text: '图片识别结果：微信支付\n早餐店 -8.50元 支付成功\n书店 -20.00元 支付成功\n合计28.50元',
      records: [
        _example(
          'expense',
          '早餐店',
          '早餐店 -8.50元 支付成功',
          amount: '8.50',
          currency: 'CNY',
          direction: 'expense',
        ),
        _example(
          'expense',
          '书店',
          '书店 -20.00元 支付成功',
          amount: '20.00',
          currency: 'CNY',
          direction: 'expense',
        ),
      ],
    ),
    (text: '支付宝订单20元，交易关闭，未支付', records: []),
    (text: '转账怎么操作？', records: []),
    (
      text: '借给小王200元',
      records: [
        _example(
          'expense',
          '借给小王',
          '借给小王200元',
          amount: '200',
          currency: 'CNY',
          direction: 'expense',
        ),
      ],
    ),
    (
      text: '李四电话13912345678',
      records: [
        _example('phone', '李四', '李四电话13912345678', phone: '13912345678'),
      ],
    ),
    (text: '提醒我买药', records: [_example('reminder', '买药', '提醒我买药')]),
  ];
  return [
    nw.systemMessage('$recordExtractionPrompt\n${RecordFields.prompt}'),
    for (final example in examples) ...[
      nw.userMessage(jsonEncode({'text': example.text})),
      nw.assistantMessage(jsonEncode({'records': example.records})),
    ],
    nw.userMessage(
      recordExtractionInput(
        '午饭花了12元\n改为15元',
        now,
        previousJson: jsonEncode([
          _example(
            'expense',
            '午饭',
            '午饭花了12元',
            amount: '12.00',
            currency: 'CNY',
            direction: 'expense',
          ),
        ]),
      ),
    ),
    nw.assistantMessage(
      jsonEncode({
        'records': [
          _example(
            'expense',
            '午饭',
            '午饭花了12元\n改为15元',
            amount: '15.00',
            currency: 'CNY',
            direction: 'expense',
          ),
        ],
      }),
    ),
    nw.userMessage(
      recordExtractionInput(
        text,
        now,
        previousJson: previousJson,
        context: context,
      ),
    ),
  ];
}
