import 'dart:io';

import 'package:ai_for_app/records/conversation_date_fact.dart';
import 'package:ai_for_app/records/direct_record_intent.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'records_test.dart' show FakeScheduler;

void main() {
  final reference = DateTime(2026, 11, 5, 23, 59);
  test(
    'anniversary statements resolve calendar dates without granting consent',
    () {
      final item = ConversationDateFact.extract('今天是ai纪念日', reference).single;
      expect(item.title, 'ai纪念日');
      expect(item.date, '2026-11-05');
      expect(item.at, isNull);
      expect(DirectRecordIntent.explicit('今天是ai纪念日'), false);
      expect(
        ConversationDateFact.extract(
          '明天是我们的结婚纪念日',
          DateTime(2026, 12, 31),
        ).single.date,
        '2027-01-01',
      );
      expect(DirectRecordIntent.explicit('记住今天是ai纪念日'), true);
    },
  );
  test('questions hypotheses and ambiguous statements do not become deterministic facts', () {
    for (final text in [
      '今天是AI纪念日吗？',
      '如果今天是AI纪念日',
      '今天不是AI纪念日',
      '可能今天是AI纪念日',
      '他说今天是AI纪念日',
      '不要记录今天是AI纪念日',
      '今天是星期四',
    ]) {
      expect(
        ConversationDateFact.extract(text, reference),
        isEmpty,
        reason: text,
      );
    }
  });
  test(
    'anniversary asks first, confirms once and never schedules a reminder',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final root = await Directory.systemTemp.createTemp('anniversary_fact');
      final store = await LocalStore.openAt(root);
      try {
        final repo = RecordRepository(store.database);
        final scheduler = FakeScheduler();
        final service = RecordService(
          repo,
          scheduler,
          (text, now) async => throw StateError(
            'No LLM should be needed for this explicit date fact',
          ),
        );
        expect(await service.extract('statement', '今天是ai纪念日', reference), 1);
        expect(await service.saveExplicit('statement'), isEmpty);
        expect(await repo.all(), isEmpty);
        final draft = (await repo.proposals()).single;
        expect(draft.question, contains('要帮你保存下来吗'));
        expect(draft.question, contains('2026年11月05日'));
        await service.decide(draft.id, accept: true);
        await service.decide(draft.id, accept: true);
        expect((await repo.all()).length, 1);
        expect(scheduler.calls, 0);
        await service.extract('request', '记住今天是ai纪念日', reference);
        expect((await service.saveExplicit('request')).length, 1);
        await service.extract('decline', '明天是旅行纪念日', reference);
        final pending = (await repo.proposals()).last;
        await service.decide(pending.id, accept: false);
        expect((await repo.all()).length, 2);
      } finally {
        await store.database.close();
        await root.delete(recursive: true);
      }
    },
  );
}
