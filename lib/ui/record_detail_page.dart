import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/local_store.dart';
import '../records/record_service.dart';
import '../records/record_templates.dart';
import 'edit_record_sheet.dart';
import 'record_media_view.dart';

class RecordDetailPage extends StatefulWidget {
  const RecordDetailPage({
    super.key,
    required this.store,
    required this.service,
    required this.row,
  });
  final LocalStore store;
  final RecordService service;
  final Map<String, Object?> row;
  @override
  State<RecordDetailPage> createState() => _RecordDetailPageState();
}

class _RecordDetailPageState extends State<RecordDetailPage> {
  late Map<String, Object?> row = widget.row;
  bool busy = false;
  String? error;
  Map<String, dynamic> get data => presentRecord(
    jsonDecode(row['payload'] as String) as Map<String, dynamic>,
  );
  Future<void> run(Future<void> Function() work) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
      final updated = await widget.service.repository.get(row['id'] as int);
      if (mounted) setState(() => row = updated);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit() async {
    final patch = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EditRecordSheet(data: data),
    );
    if (patch != null && mounted) {
      await run(() => widget.service.edit(row['id'] as int, patch));
    }
  }

  Future<void> changeTime() async {
    final now = DateTime.now();
    final old = DateTime.tryParse(data['at'] as String? ?? '')?.toLocal();
    final initial = old != null && old.isAfter(now)
        ? old
        : now.add(const Duration(hours: 1));
    final day = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateUtils.dateOnly(now),
      lastDate: DateTime(now.year + 50),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time != null && mounted) {
      await run(
        () => widget.service.changeTime(
          row['id'] as int,
          DateTime(day.year, day.month, day.day, time.hour, time.minute),
        ),
      );
    }
  }

  Future<void> remove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: Text(
          data['kind'] == 'reminder' ? '对应提醒也会取消。删除后无法恢复。' : '删除后无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.service.delete(row['id'] as int);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final source =
        widget.store.messages
                .where((m) => m['id'] == row['source_id'])
                .firstOrNull
            as Map?;
    final done = (d['fields'] as List? ?? []).any(
      (f) => f['label'] == '进度' && f['value'] == '已完成',
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('记录详情'),
        actions: [
          IconButton(
            tooltip: '编辑记录',
            onPressed: busy ? null : edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '删除记录',
            onPressed: busy ? null : remove,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (busy) const LinearProgressIndicator(),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  TweenAnimationBuilder<double>(
                    key: ValueKey(row['id']),
                    duration: Duration(
                      milliseconds: MediaQuery.disableAnimationsOf(context)
                          ? 0
                          : 240,
                    ),
                    tween: Tween(begin: 0, end: 1),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) => Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 12 * (1 - value)),
                        child: child,
                      ),
                    ),
                    child: RecordDetailContent(
                      data: d,
                      status: row['status'] as String?,
                      image: source?['image'] as String?,
                      audio: source?['audio'] as String?,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (d['kind'] == 'phone')
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: busy || d['phone'] == null
                              ? null
                              : () async {
                                  final uri = Uri(
                                    scheme: 'tel',
                                    path: d['phone'] as String,
                                  );
                                  try {
                                    if (!await launchUrl(uri)) {
                                      throw StateError('无法打开电话');
                                    }
                                  } catch (e) {
                                    if (mounted) setState(() => error = '$e');
                                  }
                                },
                          icon: const Icon(Icons.call_outlined),
                          label: const Text('拨打电话'),
                        ),
                        OutlinedButton.icon(
                          onPressed: d['phone'] == null
                              ? null
                              : () async {
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  await Clipboard.setData(
                                    ClipboardData(text: d['phone'] as String),
                                  );
                                  if (messenger.mounted) {
                                    messenger.showSnackBar(
                                      const SnackBar(content: Text('号码已复制')),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.copy),
                          label: const Text('复制号码'),
                        ),
                      ],
                    ),
                  if (d['kind'] == 'task')
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () => run(
                              () => widget.service.edit(row['id'] as int, {
                                'fields': [
                                  for (final field
                                      in d['fields'] as List? ?? [])
                                    if (field['label'] != '进度') field,
                                  {'label': '进度', 'value': done ? '待办' : '已完成'},
                                ],
                              }),
                            ),
                      icon: Icon(done ? Icons.undo : Icons.check),
                      label: Text(done ? '恢复待办' : '标记完成'),
                    ),
                  if (d['kind'] == 'reminder')
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: busy ? null : changeTime,
                          icon: const Icon(Icons.edit_calendar_outlined),
                          label: const Text('修改时间'),
                        ),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => run(
                                  () => row['status'] == 'cancelled'
                                      ? widget.service.schedule(
                                          row['id'] as int,
                                        )
                                      : widget.service.cancel(row['id'] as int),
                                ),
                          child: Text(
                            row['status'] == 'cancelled' ? '启用提醒' : '取消提醒',
                          ),
                        ),
                      ],
                    ),
                  if ((d['relatedRecordIds'] as List? ?? []).isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      '关联记录',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final id in d['relatedRecordIds'] as List)
                          ActionChip(
                            label: Text('查看关联记录 #$id'),
                            onPressed: () async {
                              try {
                                final related = await widget.service.repository
                                    .get(id as int);
                                if (!context.mounted) return;
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RecordDetailPage(
                                      store: widget.store,
                                      service: widget.service,
                                      row: related,
                                    ),
                                  ),
                                );
                              } catch (e) {
                                if (mounted) {
                                  setState(() => error = '关联记录不可用：$e');
                                }
                              }
                            },
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Composed detail surfaces: each kind leads with its meaningful content.
class RecordDetailContent extends StatelessWidget {
  const RecordDetailContent({
    super.key,
    required this.data,
    this.status,
    this.image,
    this.audio,
  });
  final Map<String, dynamic> data;
  final String? status, image, audio;
  @override
  Widget build(BuildContext context) {
    final d = presentRecord(data);
    final type = templateFor(d);
    final colors = Theme.of(context).colorScheme;
    final date =
        DateTime.tryParse(d['date'] as String? ?? '') ??
        DateTime.tryParse(d['at'] as String? ?? '')?.toLocal();
    final title = d['title'] as String? ?? '未命名记录';
    final name = switch (type) {
      'birthday' => '重要生日',
      'date' => '日程与纪念',
      'reminder' => '提醒',
      'expense' => '收支凭据',
      'phone' => '联系人',
      'task' => '待办事项',
      'image' => '影像随记',
      'audio' => '声音随记',
      _ => '文字随记',
    };
    final icon = switch (type) {
      'birthday' => Icons.cake_outlined,
      'date' => Icons.calendar_month_outlined,
      'reminder' => Icons.notifications_active_outlined,
      'expense' => Icons.receipt_long_outlined,
      'phone' => Icons.person_outline,
      'task' => Icons.check_circle_outline,
      'image' => Icons.photo_outlined,
      'audio' => Icons.graphic_eq,
      _ => Icons.notes_rounded,
    };
    Widget paper(Widget child, {bool tinted = false}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tinted ? colors.primaryContainer : colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(28),
      ),
      child: child,
    );
    Widget headline(String text, {double size = 32}) => SelectableText(
      text,
      style: TextStyle(
        fontSize: size,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: colors.onSurface,
      ),
    );
    Widget calendar() => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 80,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Text(
                date == null ? '日期' : '${date.month}月',
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                date?.day.toString() ?? '—',
                style: TextStyle(
                  fontSize: 36,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
              if (date != null)
                Text(
                  '${date.year}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              headline(title, size: 28),
              const SizedBox(height: 10),
              Text(
                d['birthdayText'] as String? ??
                    d['birthdayMonthDay'] as String? ??
                    (date == null
                        ? '日期待补充'
                        : displayDate(
                            '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                          )),
              ),
            ],
          ),
        ),
      ],
    );
    Widget primary = switch (type) {
      'birthday' => paper(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.cake_outlined, size: 40),
            const SizedBox(height: 24),
            calendar(),
            const SizedBox(height: 24),
            Text('值得记住的日子', style: TextStyle(color: colors.primary)),
          ],
        ),
        tinted: true,
      ),
      'date' => paper(calendar(), tinted: true),
      'reminder' => paper(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            headline(
              date == null
                  ? '时间待补充'
                  : '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
              size: 48,
            ),
            const SizedBox(height: 12),
            headline(title, size: 26),
            const SizedBox(height: 16),
            Text(
              date == null
                  ? '补全时间后才能设置通知'
                  : displayDate(
                      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                    ),
            ),
            const SizedBox(height: 12),
            Chip(
              avatar: const Icon(Icons.notifications_none, size: 18),
              label: Text(recordStatusLabel(status ?? 'needs_time')),
            ),
          ],
        ),
        tinted: true,
      ),
      'expense' => paper(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              d['direction'] == 'income' ? '收入' : '支出',
              style: TextStyle(color: colors.primary),
            ),
            const SizedBox(height: 12),
            headline(
              d['amountMinor'] is int
                  ? '${d['direction'] == 'income' ? '+' : '-'}${((d['amountMinor'] as int) / 100).toStringAsFixed(2)}'
                  : '金额待补充',
              size: 42,
            ),
            Text(d['currency'] as String? ?? '币种待补充'),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Divider(),
            ),
            headline(title, size: 24),
            if (d['date'] != null) ...[
              const SizedBox(height: 8),
              Text(displayDate(d['date'] as String)),
            ],
          ],
        ),
      ),
      'phone' => paper(
        Column(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: colors.primaryContainer,
              child: Icon(
                Icons.person_outline,
                size: 40,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 20),
            headline(title),
            const SizedBox(height: 16),
            SelectableText(
              d['phone'] as String? ?? '号码待补充',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                color: colors.primary,
              ),
            ),
          ],
        ),
      ),
      'task' => paper(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.task_alt, size: 40, color: colors.primary),
            const SizedBox(height: 20),
            headline(title),
            const SizedBox(height: 12),
            Text(
              (d['fields'] as List? ?? []).any(
                    (f) => f['label'] == '进度' && f['value'] == '已完成',
                  )
                  ? '已完成'
                  : '进行中的事项',
              style: TextStyle(color: colors.primary),
            ),
            if (d['date'] != null) ...[
              const SizedBox(height: 20),
              Chip(
                avatar: const Icon(Icons.event_outlined, size: 18),
                label: Text('截止 ${displayDate(d['date'] as String)}'),
              ),
            ],
          ],
        ),
        tinted: true,
      ),
      'image' => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: RecordMediaView(image: image),
            )
          else
            paper(const Text('暂无图片附件')),
          const SizedBox(height: 20),
          headline(title),
        ],
      ),
      'audio' => paper(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.graphic_eq, size: 48, color: colors.primary),
            const SizedBox(height: 24),
            headline(title, size: 28),
            const SizedBox(height: 24),
            if (audio != null)
              RecordMediaView(audio: audio)
            else
              const Text('暂无音频附件'),
          ],
        ),
      ),
      _ => paper(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            headline(title),
            if ((d['body'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 24),
              SelectableText(
                d['body'] as String,
                style: const TextStyle(fontSize: 17, height: 1.8),
              ),
            ],
          ],
        ),
      ),
    };
    return Column(
      key: ValueKey('detail-$type'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: colors.primary),
            const SizedBox(width: 8),
            Text(
              name,
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: Duration(
            milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 180,
          ),
          child: KeyedSubtree(
            key: ValueKey(
              jsonEncode([
                type,
                d['title'],
                d['at'],
                d['amountMinor'],
                d['fields'],
              ]),
            ),
            child: primary,
          ),
        ),
        if (!['image', 'audio'].contains(type) &&
            (image != null || audio != null)) ...[
          const SizedBox(height: 20),
          RecordMediaView(image: image, audio: audio),
        ],
        if (!['note'].contains(type) &&
            (d['body'] as String? ?? '').isNotEmpty) ...[
          const SizedBox(height: 20),
          paper(
            SelectableText(
              d['body'] as String,
              style: const TextStyle(fontSize: 16, height: 1.7),
            ),
          ),
        ],
        if (d['category'] != null) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              avatar: const Icon(Icons.sell_outlined, size: 16),
              label: Text(d['category'] as String),
            ),
          ),
        ],
        if ((d['fields'] as List? ?? []).isNotEmpty) ...[
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, box) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final field in d['fields'] as List)
                  if (![
                    '聊天原文',
                    '原文',
                    '聊天来源',
                    '来源消息',
                    '展示模板',
                  ].contains(field['label']))
                    SizedBox(
                      width:
                          box.maxWidth >= 320 &&
                              MediaQuery.textScalerOf(context).scale(16) <= 20
                          ? (box.maxWidth - 12) / 2
                          : box.maxWidth,
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              field['label'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              field['value'] as String,
                              style: const TextStyle(fontSize: 16, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
