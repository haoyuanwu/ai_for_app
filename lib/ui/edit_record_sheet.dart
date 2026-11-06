import 'package:flutter/material.dart';

import '../records/record_templates.dart';
import '../records/phone_record.dart';
import '../records/record_fields.dart';

class EditRecordSheet extends StatefulWidget {
  const EditRecordSheet({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  State<EditRecordSheet> createState() => _EditRecordSheetState();
}

class _EditRecordSheetState extends State<EditRecordSheet> {
  final form = GlobalKey<FormState>();
  late TextEditingController title, date, phone, amount, body, category;
  final Map<String, TextEditingController> extraControllers = {};
  Map<String, dynamic> get currentData => {
    ...widget.data,
    'template': template,
  };
  String label(String key) => RecordFields.field(currentData, key).formLabel;
  late String template;
  String? currency, direction;
  @override
  void initState() {
    super.initState();
    final d = presentRecord(widget.data);
    title = TextEditingController(text: d['title'] as String?);
    date = TextEditingController(text: d['date'] as String?);
    phone = TextEditingController(text: d['phone'] as String?);
    amount = TextEditingController(
      text: d['amountMinor'] == null
          ? ''
          : ((d['amountMinor'] as int) / 100).toStringAsFixed(2),
    );
    body = TextEditingController(text: d['body'] as String?);
    template = templateFor(d);
    category = TextEditingController(text: d['category'] as String?);
    for (final field in d['fields'] as List? ?? []) {
      extraControllers[field['label'] as String] = TextEditingController(
        text: field['value'] as String?,
      );
    }
    prepareOptionalFields();
    currency = d['currency'] as String?;
    direction = d['direction'] as String?;
  }

  @override
  void dispose() {
    for (final c in [
      title,
      date,
      phone,
      amount,
      body,
      category,
      ...extraControllers.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void prepareOptionalFields() {
    for (final field in RecordFields.forRecord(currentData)) {
      if (field.key.startsWith('extra:') || field.key == 'tags') {
        extraControllers.putIfAbsent(
          field.label,
          () => TextEditingController(),
        );
      }
    }
  }

  List<String> get visibleOptionalLabels => {
    ...RecordFields.forRecord(currentData)
        .where((field) => field.key.startsWith('extra:') || field.key == 'tags')
        .map((field) => field.label),
    ...extraControllers.entries
        .where((entry) => entry.value.text.trim().isNotEmpty)
        .map((entry) => entry.key),
  }.toList();

  bool validDate(String text) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return false;
    final v = DateTime.tryParse(text);
    return v != null && v.toIso8601String().startsWith(text);
  }

  Future<void> pickDate() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final initial = validDate(date.text) ? DateTime.parse(date.text) : now;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year < 1800 ? initial.year : 1800),
      lastDate: DateTime(
        initial.year > now.year + 100 ? initial.year : now.year + 100,
        12,
        31,
      ),
      helpText: '选择日期',
      confirmText: '确定',
      cancelText: '取消',
    );
    if (selected == null || !mounted) return;
    setState(
      () => date.text =
          '${selected.year.toString().padLeft(4, '0')}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}',
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('编辑记录', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '必填项需补齐，选填项可留空。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: title,
              decoration: InputDecoration(labelText: label('title')),
              validator: (s) => widget.data['kind'] == 'phone'
                  ? (PhoneRecord.hasName(s) ? null : '请填写联系人姓名')
                  : (s == null || s.trim().isEmpty ? '请输入标题' : null),
            ),
            const SizedBox(height: 12),
            if (widget.data['kind'] == 'reminder') ...[
              InputDecorator(
                decoration: InputDecoration(
                  labelText: label('at'),
                  helperText: '如需改期，请在记录卡片点击“修改时间”',
                ),
                child: Text(
                  DateTime.tryParse(widget.data['at'] as String? ?? '')
                          ?.toLocal()
                          .toString()
                          .substring(0, 16) ??
                      '待补充具体日期和时刻',
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (widget.data['kind'] != 'reminder') ...[
              TextFormField(
                key: const ValueKey('record-date'),
                controller: date,
                readOnly: true,
                showCursor: false,
                enableInteractiveSelection: false,
                onTap: pickDate,
                decoration: InputDecoration(
                  labelText: label('date'),
                  hintText: '点击选择日期',
                  helperText:
                      template == 'birthday' &&
                          (presentRecord(widget.data)['birthdayMonthDay'] !=
                                  null ||
                              presentRecord(widget.data)['birthdayText'] !=
                                  null)
                      ? '已提供${presentRecord(widget.data)['birthdayText'] ?? presentRecord(widget.data)['birthdayMonthDay']}；出生年份选填'
                      : RecordFields.field(currentData, 'date').required
                      ? '请选择日期；不补造未知年份'
                      : '未选择可留空，不影响保存',
                  prefixIcon: const Icon(Icons.calendar_month_outlined),
                  suffixIcon: date.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除日期',
                          onPressed: () => setState(date.clear),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                ),
                validator: (s) {
                  if (s != null && s.isNotEmpty && !validDate(s)) {
                    return '请选择有效日期';
                  }
                  final candidate = presentRecord({
                    ...currentData,
                    'date': s == null || s.isEmpty ? null : s,
                  });
                  if (RecordFields.field(currentData, 'date').required &&
                      !(s?.isNotEmpty ?? false) &&
                      candidate['at'] == null &&
                      candidate['birthdayMonthDay'] == null &&
                      candidate['birthdayText'] == null) {
                    return '请选择${RecordFields.field(currentData, 'date').label}（必填）';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
            ],
            if (widget.data['kind'] == 'phone')
              TextFormField(
                controller: phone,
                decoration: InputDecoration(labelText: label('phone')),
                keyboardType: TextInputType.phone,
                validator: (s) =>
                    s == null || !RegExp(r'^\+?[0-9 ()-]{5,25}$').hasMatch(s)
                    ? '请输入有效号码'
                    : null,
              ),
            if (widget.data['kind'] == 'expense') ...[
              TextFormField(
                controller: amount,
                decoration: InputDecoration(labelText: label('amountMinor')),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (s) =>
                    s == null ||
                        !RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(s) ||
                        (num.tryParse(s) ?? 0) <= 0
                    ? '请输入大于零、最多两位小数的金额'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: currency,
                decoration: InputDecoration(labelText: label('currency')),
                items: [
                  for (final v in ['CNY', 'USD', 'EUR', 'HKD', 'JPY', 'GBP'])
                    DropdownMenuItem(value: v, child: Text(v)),
                ],
                onChanged: (s) => currency = s,
                validator: (s) => s == null ? '请选择币种' : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: direction,
                decoration: InputDecoration(labelText: label('direction')),
                items: const [
                  DropdownMenuItem(value: 'income', child: Text('收入')),
                  DropdownMenuItem(value: 'expense', child: Text('支出')),
                ],
                onChanged: (s) => direction = s,
                validator: (s) => s == null ? '请选择收支' : null,
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: body,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(labelText: label('body')),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              key: ValueKey('optional-fields-$template'),
              tilePadding: EdgeInsets.zero,
              title: const Text('更多选填信息'),
              subtitle: Text(
                '分类、${visibleOptionalLabels.take(3).join('、')}等；无需全部填写',
              ),
              children: [
                TextFormField(
                  controller: category,
                  maxLength: 30,
                  decoration: InputDecoration(labelText: label('category')),
                ),
                for (final name in visibleOptionalLabels)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextFormField(
                      key: ValueKey('record-extra-$name'),
                      controller: extraControllers[name],
                      maxLength: 300,
                      decoration: InputDecoration(labelText: '$name（选填）'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                final patch = <String, dynamic>{
                  'title': title.text.trim(),
                  'template': template,
                  'body': body.text.trim(),
                  'category': category.text.trim().isEmpty
                      ? null
                      : category.text.trim(),
                  'fields': [
                    for (final entry in extraControllers.entries)
                      if (entry.value.text.trim().isNotEmpty)
                        {'label': entry.key, 'value': entry.value.text.trim()},
                  ],
                };
                if (widget.data['kind'] != 'reminder') {
                  patch['date'] = date.text.isEmpty ? null : date.text;
                }
                if (widget.data['kind'] == 'phone') {
                  patch['phone'] = phone.text.trim();
                }
                if (widget.data['kind'] == 'expense') {
                  final parts = amount.text.split('.');
                  patch.addAll({
                    'amountMinor':
                        int.parse(parts.first) * 100 +
                        int.parse(
                          (parts.length == 1 ? '0' : parts[1]).padRight(2, '0'),
                        ),
                    'currency': currency,
                    'direction': direction,
                  });
                }
                Navigator.pop(context, patch);
              },
              child: const Text('保存修改'),
            ),
          ],
        ),
      ),
    ),
  );
}
