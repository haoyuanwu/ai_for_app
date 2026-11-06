import 'dart:io';

import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/records/duplicate_bill.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'records_test.dart' show FakeScheduler;

void main() {
  Map<String, dynamic> bill(
    String time, {
    int amount = 2500,
    String currency = 'CNY',
    String direction = 'expense',
  }) => {
    'kind': 'expense',
    'title': '午饭',
    'amountMinor': amount,
    'currency': currency,
    'direction': direction,
    'date': '2026-11-06',
    'fields': [
      {'label': '交易时间', 'value': time},
    ],
  };
  test(
    'matches original trade time and minor units; distinguishes other trades',
    () {
      final saved = bill('2026-11-06 12:30:10');
      expect(
        DuplicateBill.matches(bill('2026 年 11 月 6 日 12:30:10'), saved),
        isTrue,
      );
      expect(
        DuplicateBill.matches(bill('2026-11-06 12:31:10'), saved),
        isFalse,
      );
      expect(
        DuplicateBill.matches(bill('2026-11-06 12:30:11'), saved),
        isFalse,
      );
      expect(
        DuplicateBill.matches(bill('2026-11-06 12:30:10', amount: 2600), saved),
        isFalse,
      );
      expect(
        DuplicateBill.matches(
          bill('2026-11-06 12:30:10', currency: 'USD'),
          saved,
        ),
        isFalse,
      );
      expect(
        DuplicateBill.matches(
          bill('2026-11-06 12:30:10', direction: 'income'),
          saved,
        ),
        isFalse,
      );
      expect(
        DuplicateBill.matches({...saved, 'fields': [], 'date': null}, saved),
        isFalse,
      );
      expect(DuplicateBill.matches({...saved, 'fields': []}, saved), isTrue);
    },
  );

  test('automatic and explicit saves stop at duplicate warning; confirmation allows one new copy', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final root = await Directory.systemTemp.createTemp('duplicate_bills');
    final store = await LocalStore.openAt(root);
    try {
      final repo = RecordRepository(store.database);
      final service = RecordService(
        repo,
        FakeScheduler(),
        (text, now) async => [],
      );
      const expense = ExtractedRecord(
        kind: RecordKind.expense,
        title: '午饭',
        quote: '午饭实付25元',
        amountMinor: 2500,
        currency: 'CNY',
        direction: 'expense',
        date: '2026-11-06',
        fields: [
          {'label': '交易时间', 'value': '2026-11-06 12:30:10'},
        ],
      );
      await repo.insert('old', [expense]);
      await repo.propose('new', [expense], context: '帮我记录午饭实付25元');
      expect(await service.saveExplicit('new', automatic: true), isEmpty);
      expect(await service.saveExplicit('new'), isEmpty);
      var draft = (await repo.proposals()).single;
      expect(draft.duplicateRecordIds, hasLength(1));
      expect(draft.question, contains('可能是同一笔'));
      expect(draft.question, contains('仍要再记录一次吗'));
      expect(await repo.all(), hasLength(1));
      expect(await service.decide(draft.id, accept: true), hasLength(1));
      expect(await service.decide(draft.id, accept: true), isEmpty);
      expect(await repo.all(), hasLength(2));
      // A manually approved old question must be re-confirmed if a duplicate
      // appeared only after that question was composed.
      await repo.propose('late', [expense], context: '午饭实付25元');
      draft = (await repo.proposals()).last;
      await expectLater(
        service.decide(draft.id, accept: true),
        throwsStateError,
      );
      expect(await repo.all(), hasLength(2));
      expect((await repo.proposals()).last.duplicateRecordIds, hasLength(2));
      await service.decide(draft.id, accept: false);
      expect(await repo.all(), hasLength(2));
    } finally {
      await store.database.close();
      await root.delete(recursive: true);
    }
  });
}
