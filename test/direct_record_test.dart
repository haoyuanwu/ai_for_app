import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/records/direct_record_intent.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';

import 'records_test.dart' show FakeScheduler;

void main() {
  test('only definite user requests count as direct consent', () {
    for (final s in ['帮我记一下今天午饭20元', '记录今天午饭20元', '明天九点提醒我买药']) {
      expect(DirectRecordIntent.explicit(s), isTrue);
    }
    for (final s in [
      '今天午饭20元',
      '如果我说帮我记一下',
      '不要记录今天午饭20元',
      '大概花了20元，帮我记一下',
      '帮我记一下可以吗？',
    ]) {
      expect(DirectRecordIntent.explicit(s), isFalse);
    }
  });
  test('explicit complete records save once, uncertain and incomplete records stay pending', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = await Directory.systemTemp.createTemp('direct_record');
    final store = await LocalStore.openAt(root);
    try {
      final repo = RecordRepository(store.database);
      final scheduler = FakeScheduler();
      final service = RecordService(repo, scheduler, (text, now) async => []);
      const expense = ExtractedRecord(
        kind: RecordKind.expense,
        title: '午饭',
        quote: '午饭20元',
        amountMinor: 2000,
        currency: 'CNY',
        direction: 'expense',
      );
      await repo.propose('a', [expense], context: '帮我记一下，午饭20元');
      expect((await service.saveExplicit('a')).length, 1);
      expect(await service.saveExplicit('a'), isEmpty);
      await repo.propose('b', [expense], context: '大概午饭20元，帮我记一下');
      expect(await service.saveExplicit('b'), isEmpty);
      await repo.propose('c', [
        const ExtractedRecord(
          kind: RecordKind.reminder,
          title: '买药',
          quote: '明天提醒我买药',
        ),
      ], context: '明天提醒我买药');
      expect(await service.saveExplicit('c'), isEmpty);
      expect(scheduler.requests, isEmpty);
      final draft = (await repo.proposals()).singleWhere(
        (p) => p.sourceId == 'c',
      );
      expect(draft.question, contains('还需要补充'));
      expect(draft.question, isNot(contains('是否记录')));
      final at = DateTime.now().add(const Duration(days: 1));
      await repo.revise(draft.id, 'c-update', '明天提醒我买药\n明天上午九点', [
        ExtractedRecord(
          kind: RecordKind.reminder,
          title: '买药',
          quote: '明天提醒我买药',
          at: at,
        ),
      ]);
      expect((await service.saveExplicit('c')).length, 1);
      expect(scheduler.requests.length, 1);
      expect((await repo.all()).length, 2);
      await repo.propose('auto', [expense], context: '今天午饭20元');
      expect(await service.saveExplicit('auto'), isEmpty);
      expect(await service.saveExplicit('auto', automatic: true), hasLength(1));
      expect(await service.saveExplicit('auto', automatic: true), isEmpty);
      for (final context in [
        '大概午饭20元',
        '不要记录午饭20元',
        '如果午饭20元',
        '他说午饭20元',
        '午饭20元？',
      ]) {
        await repo.propose(context, [expense], context: context);
        expect(await service.saveExplicit(context, automatic: true), isEmpty);
      }
      await repo.propose('missing', [
        const ExtractedRecord(
          kind: RecordKind.expense,
          title: '午饭',
          quote: '午饭花了钱',
          currency: 'CNY',
          direction: 'expense',
        ),
      ], context: '午饭花了钱');
      expect(await service.saveExplicit('missing', automatic: true), isEmpty);
    } finally {
      await store.database.close();
      await root.delete(recursive: true);
    }
  });
}
