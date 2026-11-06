import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/main.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/records/record_dialogue.dart';
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
    root = await Directory.systemTemp.createTemp('question_interaction');
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
        kind: RecordKind.expense,
        title: '午饭',
        quote: '午饭30元',
        amountMinor: 3000,
        currency: 'CNY',
        direction: 'expense',
      ),
      const ExtractedRecord(kind: RecordKind.task, title: '旅行', quote: '旅行'),
    ]);
  });
  tearDown(() async {
    await store.database.close();
    await root.delete(recursive: true);
  });
  void markQuestion(String text) {
    final p = store.data['recordInteraction'] as Map;
    store.messages.add({
      'role': 'assistant',
      'kind': 'record_question',
      'text': text,
      'status': 'done',
      'interactionToken': p['token'],
    });
  }

  test('ordinal answers retain original modification and stop after unrelated question', () async {
    final dialogue = RecordDialogue(store, service);
    final question = (await dialogue.handle('把午饭金额改成25元'))!;
    markQuestion(question);
    expect(await dialogue.handle('确认'), contains('请先点击'));
    expect(store.data['pendingDeletion'], isNull);
    final ids = List<int>.from((store.data['recordInteraction'] as Map)['ids']);
    expect(await dialogue.handle('第二条'), contains('已更新原记录'));
    expect(
      jsonDecode((await repo.get(ids[1]))['payload'] as String)['amountMinor'],
      2500,
    );
    expect(
      jsonDecode((await repo.get(ids[0]))['payload'] as String)['amountMinor'],
      3000,
    );
    expect(store.data['recordInteraction'], isNull);
    markQuestion((await dialogue.handle('删除午饭'))!);
    store.messages.add({
      'role': 'assistant',
      'kind': 'record_receipt',
      'text': '聊聊其他事情？',
    });
    expect(dialogue.followup('第二条'), isNull);
    expect((await repo.all()).length, 3);
  });
  test(
    'link selection supports two successive picks without creating records',
    () async {
      final dialogue = RecordDialogue(store, service);
      markQuestion((await dialogue.handle('把午饭关联到旅行'))!);
      expect(await dialogue.handle('第一条'), contains('第一条记录'));
      final p = store.data['recordInteraction'] as Map;
      final first = (p['selectedIds'] as List).single as int;
      markQuestion('再选另一条');
      final options = p['options'] as List;
      final other = (options.firstWhere((o) => o['id'] != first))['id'] as int;
      expect(await dialogue.handle('选择记录 #$other'), contains('已关联'));
      expect((await repo.all()).length, 3);
      expect(
        jsonDecode(
          (await repo.get(first))['payload'] as String,
        )['relatedRecordIds'],
        [other],
      );
    },
  );
  test(
    'selection context persists and can be cancelled without changing records',
    () async {
      final dialogue = RecordDialogue(store, service);
      markQuestion((await dialogue.handle('删除午饭'))!);
      await store.save();
      await store.database.close();
      store = await LocalStore.openAt(root);
      repo = RecordRepository(store.database);
      service = RecordService(repo, FakeScheduler(), (t, n) async => []);
      expect(
        RecordDialogue(store, service).followup('第二条'),
        contains('选择记录 #'),
      );
      expect(
        await RecordDialogue(store, service).handle('取消'),
        contains('已取消'),
      );
      expect(store.data['recordInteraction'], isNull);
      expect((await repo.all()).length, 3);
    },
  );
  test('missing edit value accepts the next short answer', () async {
    final dialogue = RecordDialogue(store, service);
    final rows = await repo.all();
    final id = rows.singleWhere((r) => r['kind'] == 'task')['id'] as int;
    final question = (await dialogue.handle('把记录 #$id 的标题修改一下'))!;
    markQuestion(question);
    expect(question, contains('新的标题'));
    expect(await dialogue.handle('好的'), contains('具体内容'));
    expect(await dialogue.handle('周末旅行'), contains('已更新原记录'));
    expect(
      jsonDecode((await repo.get(id))['payload'] as String)['title'],
      '周末旅行',
    );
  });
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'choice button opens review, natural yes confirms and cancellation keeps records',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(MyApp(store: store, recordService: service));
      await flush(tester);
      await tester.enterText(find.byType(TextField), '删除午饭');
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      final options =
          (store.data['recordInteraction'] as Map)['options'] as List;
      final label = options.first['label'] as String;
      await tester.scrollUntilVisible(
        find.widgetWithText(OutlinedButton, label),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.widgetWithText(OutlinedButton, label));
      await flush(tester);
      expect((await tester.runAsync(repo.all))!.length, 3);
      expect(find.widgetWithText(FilledButton, '确认删除'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '好的');
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      expect((await tester.runAsync(repo.all))!.length, 2);
      await tester.scrollUntilVisible(
        find.textContaining('已删除“午饭”'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('已删除“午饭”'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'next message supplements the pending draft without a reply button',
    (tester) async {
      await tester.runAsync(
        () => repo.propose('reminder-question', [
          const ExtractedRecord(
            kind: RecordKind.reminder,
            title: '买药',
            quote: '明天提醒我买药',
          ),
        ], context: '明天提醒我买药'),
      );
      service = RecordService(
        repo,
        FakeScheduler(),
        (t, n) async => [],
        refiner: (proposal, text, reference) async {
          expect(text, '明天上午九点');
          return [
            ExtractedRecord(
              kind: RecordKind.reminder,
              title: '买药',
              quote: proposal.context,
              at: DateTime(2026, 11, 6, 9),
            ),
          ];
        },
      );
      await tester.pumpWidget(MyApp(store: store, recordService: service));
      await flush(tester);
      expect(find.widgetWithText(TextButton, '补充信息'), findsNothing);
      await tester.enterText(find.byType(TextField), '明天上午九点');
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      final drafts = await tester.runAsync(repo.proposals);
      expect(drafts!.where((p) => p.status == 'pending'), isEmpty);
      final rows = await tester.runAsync(repo.all);
      expect(rows!.where((r) => r['kind'] == 'reminder'), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'questions have no reply button and keep the conversation input',
    (tester) async {
      store.messages.add({
        'role': 'assistant',
        'text': '需要补充其他信息吗？',
        'status': 'done',
      });
      await tester.pumpWidget(MyApp(store: store, recordService: service));
      await flush(tester);
      await tester.enterText(find.byType(TextField), '保留草稿');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.widgetWithText(TextButton, '回复'), findsNothing);
      expect(find.widgetWithText(TextButton, '补充说明'), findsNothing);
      expect(find.text('保留草稿'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
