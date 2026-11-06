import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/main.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/core/local_context.dart';
import 'package:ai_for_app/records/record_dialogue.dart';
import 'package:ai_for_app/records/record_deletion.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:ai_for_app/records/extracted_record.dart';

import 'records_test.dart' show FakeScheduler;

void main() {
  late Directory root;
  late LocalStore store;
  late RecordRepository repo;
  late RecordService service;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('record_dialogue');
    store = await LocalStore.openAt(root);
    repo = RecordRepository(store.database);
    service = RecordService(repo, FakeScheduler(), (t, n) async => []);
    await repo.insert('seed', [
      const ExtractedRecord(
        kind: RecordKind.expense,
        title: '午饭',
        quote: '午饭20元',
        amountMinor: 2000,
        currency: 'CNY',
        direction: 'expense',
      ),
      const ExtractedRecord(
        kind: RecordKind.task,
        title: '杭州旅行',
        quote: '杭州旅行',
      ),
    ]);
  });
  tearDown(() async {
    await store.database.close();
    await root.delete(recursive: true);
  });
  test(
    'named query edit link delete review work without model tool calling',
    () async {
      final dialogue = RecordDialogue(store, service);
      final answer = await dialogue.handle('查一下我的午饭花了多少钱');
      expect(answer, contains('20.00'));
      expect(answer, isNot(contains('2000')));
      expect(await dialogue.handle('午饭花了多少钱'), contains('20.00'));
      expect(await dialogue.handle('把午饭金额改成25元'), contains('已更新原记录'));
      final id =
          (await repo.all()).singleWhere((r) => r['kind'] == 'expense')['id']
              as int;
      expect(
        jsonDecode((await repo.get(id))['payload'] as String)['amountMinor'],
        2500,
      );
      expect(await dialogue.handle('把午饭关联到杭州旅行'), contains('已关联'));
      expect((await repo.all()).length, 2);
      expect(await dialogue.handle('删除午饭记录'), contains('确认删除吗'));
      expect((await repo.all()).length, 2);
      final p = store.data['pendingDeletion'] as Map;
      store.messages.add({
        'role': 'assistant',
        'kind': 'deletion_proposal',
        'deletionToken': p['token'],
      });
      expect(
        await RecordDeletion.respond(store, service, '确认删除'),
        contains('已删除'),
      );
      expect((await repo.all()).length, 1);
    },
  );
  test('ambiguous names display real candidates without mutating', () async {
    await repo.insert('extra', [
      const ExtractedRecord(
        kind: RecordKind.expense,
        title: '午饭',
        quote: '午饭30元',
        amountMinor: 3000,
        currency: 'CNY',
        direction: 'expense',
      ),
    ]);
    final dialogue = RecordDialogue(store, service);
    for (final question in ['删除午饭', '把午饭金额改成25元']) {
      final result = await dialogue.handle(question);
      expect(result, contains('多条记录'));
      expect(
        jsonEncode((store.data['recordInteraction'] as Map)['options']),
        contains('20.00'),
      );
      expect(
        jsonEncode((store.data['recordInteraction'] as Map)['options']),
        contains('30.00'),
      );
    }
    expect(store.data['pendingDeletion'], isNull);
    expect((await repo.all()).length, 3);
    final id = (await repo.all()).first['id'] as int;
    expect(await dialogue.handle('删除第$id条午饭'), contains('确认删除吗'));
  });
  test('model data exposes monetary major units but storage remains integer minor units', () async {
    final page = await LocalContext(store).page('records', '午饭', 0);
    expect(page, contains('20.00'));
    expect(page, isNot(contains('amountMinor')));
    final rows = await repo.all();
    final expense = rows.singleWhere((r) => r['kind'] == 'expense');
    expect(jsonDecode(expense['payload'] as String)['amountMinor'], 2000);
  });
  testWidgets(
    'chat can query modify and review deletion without a configured model',
    (tester) async {
      await tester.pumpWidget(MyApp(store: store, recordService: service));
      Future<void> flush() async {
        for (var i = 0; i < 15; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 30));
        }
        await tester.pumpAndSettle();
      }

      await flush();
      for (final text in [
        '查一下我的午饭花了多少钱',
        '帮我记录，把午饭金额改成25元',
        '把午饭关联到杭州旅行',
        '删除午饭记录',
      ]) {
        await tester.enterText(find.byType(TextField), text);
        await tester.tap(find.byTooltip('发送'));
        await flush();
      }
      expect(
        store.messages.any((m) => (m['text'] as String).contains('已更新原记录 #')),
        isTrue,
      );
      expect(
        store.messages.any((m) => (m['text'] as String).contains('已关联')),
        isTrue,
      );
      expect(find.widgetWithText(FilledButton, '确认删除'), findsOneWidget);
      expect((await tester.runAsync(repo.all))!.length, 2);
      await tester.ensureVisible(find.widgetWithText(FilledButton, '确认删除'));
      await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
      await flush();
      expect((await tester.runAsync(repo.all))!.length, 1);
      expect(find.textContaining('已删除“午饭”'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
