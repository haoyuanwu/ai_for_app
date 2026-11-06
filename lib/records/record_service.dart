import 'dart:convert';

import 'package:synchronized/synchronized.dart';

import 'extracted_record.dart';
import 'record_repository.dart';
import 'record_confirmation.dart';
import 'direct_record_intent.dart';
import 'automatic_record_policy.dart';
import 'conversation_date_fact.dart';
import 'conversation_reminder_intent.dart';
import 'reminder_notifications.dart';

typedef RecordExtractor = Future<List<ExtractedRecord>> Function(
  String text,
  DateTime reference,
);

class RecordService {
  RecordService(
    this.repository,
    this.scheduler,
    this.extractor, {
    this.refiner,
  });
  final RecordRepository repository;
  final ReminderScheduler scheduler;
  final RecordExtractor extractor;
  final Future<List<ExtractedRecord>> Function(
    RecordProposal proposal,
    String text,
    DateTime reference,
  )?
  refiner;
  final _lock = Lock(reentrant: true);
  Future<int> extract(
    String sourceId,
    String text,
    DateTime reference, {
    RecordExtractor? extractor,
  }) => _lock.synchronized(() async {
    if (await repository.hasExtracted(sourceId)) return 0;
    final dateFacts = ConversationDateFact.extract(text, reference);
    final reminderFacts = ConversationReminderIntent.extract(text, reference);
    final records = reminderFacts.isNotEmpty
        ? reminderFacts
        : dateFacts.isNotEmpty
        ? dateFacts
        : await (extractor ?? this.extractor)(text, reference);
    return repository.propose(sourceId, records, context: text);
  });

  Future<void> refine(
    RecordProposal proposal,
    String updateId,
    String text,
    DateTime reference,
  ) => _lock.synchronized(() async {
    if (await repository.hasExtracted(updateId)) return;
    if (refiner == null) throw StateError('当前无法补充内容，请配置本地模型');
    final records = await refiner!(proposal, text, reference);
    await repository.revise(
      proposal.id,
      updateId,
      '${proposal.context}\n$text',
      records,
    );
  });

  /// Commit explicit requests or enabled automatic facts; uncertain or incomplete
  /// drafts stay pending. Decisions and scheduling remain idempotent.
  Future<List<int>> saveExplicit(
    String sourceId, {
    String? intentText,
    bool automatic = false,
  }) => _lock.synchronized(() async {
    final result = <int>[];
    for (final proposal in await repository.proposals()) {
      if (proposal.sourceId != sourceId ||
          proposal.status != 'pending' ||
          proposal.missingFields.isNotEmpty ||
          !(DirectRecordIntent.explicit(intentText ?? proposal.context) ||
              (automatic &&
                  AutomaticRecordPolicy.allows(
                    intentText ?? proposal.context,
                  ) &&
                  AutomaticRecordPolicy.allows(proposal.context)))) {
        continue;
      }
      if (!automatic &&
          !DirectRecordIntent.recordVerb(intentText ?? proposal.context) &&
          proposal.items.any((item) => item['kind'] != 'reminder')) {
        continue;
      }
      if (proposal.items.any(
        (item) =>
            item['kind'] == 'reminder' &&
            !DateTime.parse(item['at'] as String).isAfter(DateTime.now()),
      )) {
        continue;
      }
      if ((await repository.refreshDuplicateWarnings(proposal.id))
          .duplicateRecordIds
          .isNotEmpty) {
        continue;
      }
      result.addAll(await decide(proposal.id, accept: true));
    }
    return result;
  });

  Future<List<int>> decide(
    int proposalId, {
    required bool accept,
  }) => _lock.synchronized(() async {
    final before = (await repository.proposals()).singleWhere(
      (p) => p.id == proposalId,
    );
    if (accept) await repository.refreshDuplicateWarnings(proposalId);
    final ids = await repository.decide(
      proposalId,
      accept: accept,
      allowedDuplicateIds: before.duplicateRecordIds,
    );
    // Only records committed by an explicit decision can reach OS scheduling.
    for (final id in ids) {
      if ((await repository.get(id))['kind'] == 'reminder') await schedule(id);
    }
    return ids;
  });

  Future<void> schedule(
    int id, {
    bool requestPermission = true,
  }) => _lock.synchronized(() async {
    final row = await repository.get(id);
    if (row['kind'] != 'reminder') return;
    final data = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    final at = data['at'] == null ? null : DateTime.parse(data['at'] as String);
    if (at == null) {
      await repository.status(id, 'needs_time');
      return;
    }
    if (!at.isAfter(DateTime.now())) {
      await repository.status(id, 'elapsed');
      return;
    }
    try {
      final status = await scheduler.schedule(
        id,
        data['title'] as String,
        at,
        requestPermission: requestPermission,
      );
      await repository.status(id, status);
    } catch (e) {
      await repository.status(id, 'failed', '$e');
    }
  });

  Future<void> edit(int id, Map<String, dynamic> patch) =>
      _lock.synchronized(() async {
        final row = await repository.get(id);
        await repository.edit(id, patch);
        if (row['kind'] == 'reminder' &&
            [
              'scheduled',
              'scheduled_inexact',
              'pending',
            ].contains(row['status'])) {
          await schedule(id, requestPermission: false);
        }
      });

  Future<void> changeTime(int id, DateTime at) => _lock.synchronized(() async {
    if (!at.isAfter(DateTime.now())) throw StateError('请选择未来时间');
    // Cancel the old OS request before changing the persisted timestamp.
    await scheduler.cancel(id);
    await repository.setTime(id, at);
    await schedule(id);
  });

  Future<void> cancel(int id) => _lock.synchronized(() async {
    await repository.status(id, 'cancelled');
    try {
      await scheduler.cancel(id);
    } catch (e) {
      await repository.status(id, 'cancel_failed', '$e');
      rethrow;
    }
  });

  Future<void> delete(int id, {String? expectedPayload}) =>
      _lock.synchronized(() async {
        final row = await repository.get(id);
        if (expectedPayload != null && row['payload'] != expectedPayload) {
          throw StateError('记录已变化，请重新确认');
        }
        if (row['kind'] == 'reminder') await cancel(id);
        await repository.delete(id);
      });

  /// Idempotent OS ids recover a crash between DB insertion and scheduling.
  /// No permission dialog or model inference is started on app resume.
  Future<void> recover() => _lock.synchronized(() async {
    for (final row in await repository.all()) {
      final status = row['status'];
      if (row['kind'] != 'reminder') continue;
      final id = row['id'] as int;
      if (status == 'cancel_failed') {
        try {
          await cancel(id);
        } catch (_) {}
      }
      if (['pending', 'scheduled', 'scheduled_inexact'].contains(status)) {
        await schedule(id, requestPermission: false);
      }
    }
  });
}

String recordStatusLabel(String status) =>
    const {
      'saved': '已保存',
      'needs_time': '待补充提醒时间',
      'pending': '等待调度',
      'scheduled': '已调度',
      'scheduled_inexact': '已调度 · 系统可能延迟',
      'failed': '提醒未启用',
      'elapsed': '提醒时间已过',
      'cancelled': '已取消提醒',
      'cancel_failed': '取消失败，请重试',
    }[status] ??
    status;
