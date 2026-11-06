import 'phone_record.dart';
import 'record_templates.dart';

class RecordField {
  const RecordField(
    this.key,
    this.label, {
    this.required = false,
    this.hint = '',
    this.type = 'text',
    this.alternatives = const [],
  });
  final String key, label, hint, type;
  final bool required;
  final List<String> alternatives;
  String get formLabel => '$label（${required ? '必填' : '选填'}）';
}

/// Shared by extraction prompts, incomplete-draft checks and the record editor.
/// Optional values stay absent unless supplied by the user.
class RecordFields {
  static List<RecordField> forRecord(Map<String, dynamic> data) {
    final kind = data['kind'];
    final template = templateFor(data);
    return [
      RecordField(
        'title',
        kind == 'phone'
            ? '联系人姓名'
            : kind == 'task'
            ? '事项内容'
            : '标题',
        required: true,
      ),
      if (template == 'birthday')
        const RecordField(
          'date',
          '生日日期',
          required: true,
          type: 'date',
          alternatives: ['birthdayMonthDay', 'birthdayText'],
          hint: '年月日、仅月日或农历生日均可；年份未知不补造',
        )
      else if (kind == 'reminder')
        const RecordField('at', '具体提醒日期和时刻', required: true, type: 'datetime')
      else
        RecordField(
          'date',
          kind == 'task' ? '截止日期' : '日期',
          required: kind == 'date',
          type: 'date',
          alternatives: kind == 'date' ? ['at'] : const [],
        ),
      if (kind == 'phone')
        const RecordField('phone', '电话号码', required: true, type: 'phone'),
      if (kind == 'expense') ...[
        const RecordField('amountMinor', '金额', required: true, type: 'money'),
        const RecordField('currency', '币种', required: true),
        const RecordField('direction', '收支类型', required: true),
      ],
      const RecordField('category', '分类'),
      const RecordField('body', '备注 / 正文', type: 'multiline'),
      const RecordField('template', '展示模板', hint: '未指定时由应用按内容选择'),
      if (template == 'birthday')
        ..._optional(['称呼', '关系', '出生时间', '出生地', '祝福语', '礼物偏好']),
      if (kind == 'date' && template != 'birthday')
        ..._optional([
          '地点',
          '人物',
          '日程类型',
          '开始时间',
          '结束时间',
          '组织方',
          '出行方式',
          '地址',
          '纪念意义',
        ]),
      if (kind == 'reminder')
        ..._optional(['地点', '相关人物', '优先级', '提醒原因', '准备事项', '联系方式']),
      if (kind == 'phone')
        ..._optional([
          '关系',
          '公司',
          '部门',
          '职位',
          '邮箱',
          '微信',
          '备用电话',
          '地址',
          '网址',
          '联系偏好',
        ]),
      if (kind == 'task')
        ..._optional([
          '负责人',
          '参与人',
          '地点',
          '优先级',
          '进度',
          '开始日期',
          '完成日期',
          '项目',
          '子事项',
          '预计耗时',
        ]),
      if (kind == 'expense')
        ..._optional([
          '商户',
          '付款账户',
          '支付方式',
          '收款方',
          '交易时间',
          '项目',
          '发票号码',
          '订单号',
          '报销状态',
          '数量',
          '单价',
        ]),
      if (kind == 'note' && !['birthday', 'image', 'audio'].contains(template))
        ..._optional(['主题', '人物', '地点', '事件时间', '关键词', '网址', '来源', '项目']),
      if (template == 'image') ...[
        const RecordField(
          'image',
          '图片附件',
          type: 'attachment',
          hint: '由实际消息附件提供，不允许模型编造文件路径',
        ),
        ..._optional(['图片说明', '拍摄时间', '拍摄地点', '人物', '识别文字', '相册', '来源']),
      ],
      if (template == 'audio') ...[
        const RecordField(
          'audio',
          '音频附件',
          type: 'attachment',
          hint: '由实际消息附件提供，不允许模型编造文件路径',
        ),
        ..._optional([
          '音频标题',
          '录音时间',
          '说话人',
          '语言',
          '转写内容',
          '摘要',
          '关键词',
          '录音地点',
        ]),
      ],
      const RecordField('tags', '标签', hint: '多个标签用逗号分隔'),
    ];
  }

  static Iterable<RecordField> _optional(List<String> labels) =>
      labels.map((label) => RecordField('extra:$label', label));
  static RecordField field(Map<String, dynamic> data, String key) =>
      forRecord(data).firstWhere(
        (field) => field.key == key,
        orElse: () => RecordField(key, key),
      );
  static bool _present(dynamic value) =>
      value != null && (value is! String || value.trim().isNotEmpty);

  static List<String> missing(Map<String, dynamic> raw) {
    final data = presentRecord(raw);
    final result = <String>[];
    for (final field in forRecord(data).where((f) => f.required)) {
      var present =
          _present(data[field.key]) ||
          field.alternatives.any((key) => _present(data[key]));
      if (field.key == 'title' && data['kind'] == 'phone') {
        present = PhoneRecord.hasName(data['title']);
      }
      if (field.key == 'phone') present = PhoneRecord.hasNumber(data['phone']);
      if (field.key == 'amountMinor') {
        present =
            data['amountMinor'] is int && (data['amountMinor'] as int) > 0;
      }
      if (field.key == 'currency') {
        present = [
          'CNY',
          'USD',
          'EUR',
          'HKD',
          'JPY',
          'GBP',
        ].contains(data['currency']);
      }
      if (field.key == 'direction') {
        present = ['income', 'expense'].contains(data['direction']);
      }
      if (present) continue;
      if (field.key == 'title' && data['kind'] == 'phone') {
        result.add('联系人的姓名');
        continue;
      }
      if (field.key == 'phone' && !PhoneRecord.hasName(data['title'])) {
        result.add('电话号码');
        continue;
      }
      if (field.key == 'direction') {
        result.add('“${data['title']}”是收入还是支出');
        continue;
      }
      result.add('“${data['title'] ?? '记录'}”的${field.label}');
    }
    return result;
  }

  static List<String> optionalLabels(Map<String, dynamic> data) =>
      forRecord(data)
          .where((f) => !f.required && f.type != 'attachment')
          .map((f) => f.label)
          .toList();
  static String get prompt => [
    '记录必填与选填规则：必填项缺失用 null 并等待补充；选填项仅在用户提供时提取，不能为了凑字段而猜测或连续追问。',
    for (final (kind, template) in [
      ('date', 'birthday'),
      ('date', 'date'),
      ('reminder', 'reminder'),
      ('phone', 'phone'),
      ('task', 'task'),
      ('expense', 'expense'),
      ('note', 'note'),
      ('note', 'image'),
      ('note', 'audio'),
    ])
      '$template：必填 ${forRecord({'kind': kind, 'template': template}).where((f) => f.required).map((f) => f.label).join('、')}；选填 ${optionalLabels({'kind': kind, 'template': template}).join('、')}。',
    '日期、电话、金额、币种、收支填写标准字段；分类用 category，备注用 body，其余选填信息放 fields 的 label/value。fields 的值必须逐字来自 quote；未提供的不输出。图片音频路径由应用提供。重复提醒仅作为文字偏好，不能声称已启用；通知仅在用户明确要求提醒时创建。',
  ].join('\n');
}
