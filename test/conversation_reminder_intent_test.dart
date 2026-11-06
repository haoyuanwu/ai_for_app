import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/records/conversation_reminder_intent.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:ai_for_app/records/record_repository.dart';

import 'records_test.dart' show FakeScheduler;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test('afternoon one resolves 13:00 and extracts coffee task', () {
    final record = ConversationReminderIntent.extract(
      '下午一点提醒我买咖啡',
      DateTime(2030, 1, 1, 10),
    ).single;
    expect(record.title, '买咖啡');
    expect(record.at, DateTime(2030, 1, 1, 13));
  });
  test('past or vague time stays a draft without guessing tomorrow', () {
    final past = ConversationReminderIntent.extract(
      '下午一点提醒我买咖啡',
      DateTime(2030, 1, 1, 15),
    ).single;
    expect(past.at, isNull);
    expect(past.body, contains('已经过去'));
    expect(
      ConversationReminderIntent.extract(
        '明天提醒我买咖啡',
        DateTime(2030, 1, 1, 10),
      ).single.at,
      isNull,
    );
    expect(
      ConversationReminderIntent.extract(
        '提醒我买一点咖啡',
        DateTime(2030, 1, 1, 10),
      ).single.at,
      isNull,
    );
  });
  test('handles clock after intent and rejects negative, hypothetical and mixed facts', () {
    expect(
      ConversationReminderIntent.extract(
        '提醒我明天下午一点买咖啡',
        DateTime(2030, 1, 1, 10),
      ).single.title,
      '买咖啡',
    );
    for (final text in [
      '不要下午一点提醒我买咖啡',
      '如果下午一点提醒我买咖啡',
      '下午一点提醒我买咖啡？',
      '午饭20元，下午一点提醒我买咖啡',
    ]) {
      expect(
        ConversationReminderIntent.extract(text, DateTime(2030, 1, 1, 10)),
        isEmpty,
      );
    }
  });
  test('explicit reminder bypasses empty model extraction, saves and schedules once', () async {
    final dir = await Directory.systemTemp.createTemp('coffee_reminder');
    final store = await LocalStore.openAt(dir);
    final scheduler = FakeScheduler();
    try {
      final repo = RecordRepository(store.database);
      final service = RecordService(
        repo,
        scheduler,
        (_, _) async => throw StateError('model must not be required'),
      );
      expect(
        await service.extract('coffee', '下午一点提醒我买咖啡', DateTime(2030, 1, 1, 10)),
        1,
      );
      expect(await service.saveExplicit('coffee'), hasLength(1));
      expect(await repo.all(), hasLength(1));
      expect(scheduler.calls, 1);
      expect(
        scheduler.requests.values.single.toLocal(),
        DateTime(2030, 1, 1, 13),
      );
      expect(await service.saveExplicit('coffee'), isEmpty);
      expect(scheduler.calls, 1);
    } finally {
      await store.database.close();
      await dir.delete(recursive: true);
    }
  });
}
