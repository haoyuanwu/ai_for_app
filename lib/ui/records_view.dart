import 'dart:convert';
import 'dart:io';

import '../records/reminder_notifications.dart';

import 'package:flutter/material.dart';

import '../core/local_store.dart';
import '../records/extracted_record.dart';
import 'record_data_view.dart';
import 'record_media_view.dart';
import 'edit_record_sheet.dart';
import 'record_detail_page.dart';
import '../records/record_templates.dart';
import '../records/record_service.dart';

class RecordsView extends StatefulWidget {
  const RecordsView({
    super.key,
    required this.store,
    required this.service,
    this.initialRecordIds = const [],
  });
  final LocalStore store;
  final List<int> initialRecordIds;
  final RecordService service;
  @override
  State<RecordsView> createState() => _RecordsViewState();
}

class _RecordsViewState extends State<RecordsView> {
  List<Map<String, Object?>> rows = [];
  RecordKind? filter;
  bool loading = true, working = false;
  late Set<int> focusedIds;
  String? error;
  @override
  void initState() {
    super.initState();
    focusedIds = widget.initialRecordIds.toSet();
    load();
  }

  Future<void> load() async {
    try {
      final result = await widget.service.repository.all();
      if (mounted) {
        setState(() {
          rows = result;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '读取失败：$e';
          loading = false;
        });
      }
    }
  }

  Future<void> action(Future<void> Function() fn) async {
    setState(() {
      working = true;
      error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
    await load();
    if (mounted) setState(() => working = false);
  }

  Future<void> time(int id, Map<String, dynamic> data) async {
    final now = DateTime.now();
    final old = DateTime.tryParse(data['at'] as String? ?? '')?.toLocal();
    final initial = old != null && old.isAfter(now)
        ? old
        : now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: '选择单次提醒日期',
    );
    if (date == null || !mounted) return;
    final clock = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: '选择提醒时间（本地时区）',
    );
    if (clock == null) return;
    await action(
      () => widget.service.changeTime(
        id,
        DateTime(date.year, date.month, date.day, clock.hour, clock.minute),
      ),
    );
  }

  Future<bool> confirmDelete({bool reminder = false}) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除这条记录？'),
          content: Text(
            reminder ? '对应的待触发提醒也会取消。删除后无法恢复，聊天原文会保留。' : '删除后无法恢复，聊天原文会保留。',
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
      ) ??
      false;

  Future<void> delete(int id, {required bool reminder}) async {
    if (await confirmDelete(reminder: reminder) && mounted) {
      await action(() => widget.service.delete(id));
    }
  }

  Future<void> deleteNote(dynamic note) async {
    if (!await confirmDelete() || !mounted) return;
    await action(() async {
      final index = widget.store.notes.indexOf(note);
      if (index < 0) return;
      widget.store.notes.removeAt(index);
      try {
        await widget.store.save();
      } catch (_) {
        widget.store.notes.insert(index, note);
        rethrow;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = rows
        .where(
          (r) =>
              (focusedIds.isEmpty || focusedIds.contains(r['id'])) &&
              (filter == null || r['kind'] == filter!.name),
        )
        .toList();
    final totals = <String, int>{};
    for (final r in rows.where(
      (r) =>
          r['kind'] == 'expense' &&
          (focusedIds.isEmpty || focusedIds.contains(r['id'])),
    )) {
      final d = jsonDecode(r['payload'] as String) as Map<String, dynamic>;
      if (d['amountMinor'] != null &&
          d['currency'] != null &&
          d['direction'] != null) {
        final key =
            '${d['currency']} ${d['direction'] == 'income' ? '收入' : '支出'}';
        totals[key] = (totals[key] ?? 0) + (d['amountMinor'] as int);
      }
    }
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${visible.length} 条记录',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              IconButton(
                tooltip: '刷新记录',
                onPressed: working ? null : load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (focusedIds.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() {
                focusedIds.clear();
                filter = null;
              }),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('查看全部记录'),
            ),
          if (Platform.isAndroid &&
              widget.service.scheduler is ReminderNotifications)
            TextButton.icon(
              onPressed: working
                  ? null
                  : () => action(() async {
                      final allowed =
                          await (widget.service.scheduler
                                  as ReminderNotifications)
                              .requestExactPermission();
                      if (!allowed) throw StateError('未开启精确定时，现有提醒仍可能延迟');
                      await widget.service.recover();
                    }),
              icon: const Icon(Icons.alarm),
              label: const Text('允许精确定时'),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('全部'),
                selected: filter == null,
                onSelected: (_) => setState(() => filter = null),
              ),
              for (final kind in RecordKind.values)
                ChoiceChip(
                  label: Text(kind.label),
                  selected: filter == kind,
                  onSelected: (_) => setState(() => filter = kind),
                ),
            ],
          ),
          if (filter == null || filter == RecordKind.expense)
            ...totals.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${e.key}：${(e.value / 100).toStringAsFixed(2)}'),
              ),
            ),
          if (loading || working) const LinearProgressIndicator(),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!loading && visible.isEmpty)
            Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                focusedIds.isNotEmpty
                    ? '这条记录已删除或不再存在。'
                    : '还没有记录，随时在对话中记下想留存的内容。',
              ),
            ),
          for (final row in visible) recordCard(row),
          if (focusedIds.isEmpty &&
              filter == null &&
              widget.store.notes.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('手动收藏'),
            ),
            for (final note in widget.store.notes.reversed)
              legacyCard(note as Map<String, dynamic>),
          ],
        ],
      ),
    );
  }

  Widget legacyCard(Map<String, dynamic> note) {
    final data = presentRecord({
      'kind': 'note',
      'title': (note['text'] as String? ?? '').contains('生日')
          ? '生日'
          : note['category'] ?? '文字记录',
      'quote': note['text'] ?? '',
      ...note,
    });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RecordDataView(data: data, hideChatSource: true),
            RecordMediaView(
              image: note['image'] as String?,
              audio: note['audio'] as String?,
            ),
            Wrap(
              children: [
                IconButton(
                  tooltip: '编辑内容',
                  onPressed: working
                      ? null
                      : () async {
                          final patch =
                              await showModalBottomSheet<Map<String, dynamic>>(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) => EditRecordSheet(data: data),
                              );
                          if (patch != null && mounted) {
                            await action(() async {
                              final old = Map<String, dynamic>.from(note);
                              note.addAll(patch);
                              try {
                                await widget.store.save();
                              } catch (_) {
                                note
                                  ..clear()
                                  ..addAll(old);
                                rethrow;
                              }
                            });
                          }
                        },
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: '删除收藏',
                  onPressed: working ? null : () => deleteNote(note),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> openDetail(Map<String, Object?> row) async {
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => RecordDetailPage(
          store: widget.store,
          service: widget.service,
          row: row,
        ),
        transitionDuration: Duration(
          milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 240,
        ),
        reverseTransitionDuration: Duration(
          milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 180,
        ),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, .025), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
        ),
      ),
    );
    if (mounted) await load();
  }

  Widget recordCard(Map<String, Object?> row) {
    final d = presentRecord(
      jsonDecode(row['payload'] as String) as Map<String, dynamic>,
    );
    final kind = RecordKind.values.byName(row['kind'] as String);
    final id = row['id'] as int;
    final status = row['status'] as String;
    final at = DateTime.tryParse(d['at'] as String? ?? '')?.toLocal();
    return Card(
      key: ValueKey('record-$id'),
      margin: const EdgeInsets.only(top: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => openDetail(row),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RecordDataView(data: d, hideChatSource: true, compact: true),
              if ((d['relatedRecordIds'] as List? ?? []).isNotEmpty)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final relatedId in d['relatedRecordIds'] as List)
                      Chip(
                        label: Text(
                          '关联：${rows.where((r) => r['id'] == relatedId).map((r) => (jsonDecode(r['payload'] as String) as Map)['title']).firstOrNull ?? '已删除记录'}',
                        ),
                      ),
                  ],
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      recordStatusLabel(status),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: '查看详情',
                    onPressed: working ? null : () => openDetail(row),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  ),
                  IconButton(
                    tooltip: '编辑内容',
                    onPressed: working
                        ? null
                        : () async {
                            final patch =
                                await showModalBottomSheet<
                                  Map<String, dynamic>
                                >(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => EditRecordSheet(data: d),
                                );
                            if (patch != null && mounted) {
                              await action(
                                () => widget.service.edit(id, patch),
                              );
                            }
                          },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '删除记录',
                    onPressed: working
                        ? null
                        : () =>
                              delete(id, reminder: kind == RecordKind.reminder),
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ],
              ),
              if (row['error'] != null)
                Text(
                  row['error'] as String,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (kind == RecordKind.reminder)
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: working ? null : () => time(id, d),
                      icon: const Icon(Icons.edit_calendar_outlined),
                      label: Text(at == null ? '补充提醒时间' : '修改时间'),
                    ),
                    if (['failed', 'pending', 'cancelled'].contains(status) &&
                        at != null)
                      TextButton(
                        onPressed: working
                            ? null
                            : () => action(() => widget.service.schedule(id)),
                        child: const Text('启用 / 重试'),
                      ),
                    if ([
                      'scheduled',
                      'scheduled_inexact',
                      'pending',
                      'failed',
                      'cancel_failed',
                    ].contains(status))
                      TextButton(
                        onPressed: working
                            ? null
                            : () => action(() => widget.service.cancel(id)),
                        child: Text(
                          status == 'cancel_failed' ? '重试取消' : '取消提醒',
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
