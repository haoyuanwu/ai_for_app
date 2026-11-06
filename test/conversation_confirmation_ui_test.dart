import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/main.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';

import 'records_test.dart' show FakeScheduler;

void main() {
  late Directory directory;
  late LocalStore store;
  late RecordRepository repo;
  late RecordService service;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('confirm_ui');
    store = await LocalStore.openAt(directory);
    repo = RecordRepository(store.database);
    service = RecordService(
      repo,
      FakeScheduler(),
      (text, now) async =>
          throw StateError('should not need a model for approval'),
    );
    await repo.propose('message1', [
      const ExtractedRecord(
        kind: RecordKind.expense,
        title: '午饭',
        quote: '午饭花了20元',
        amountMinor: 2000,
        currency: 'CNY',
        direction: 'expense',
      ),
    ], context: '午饭花了20元');
  });
  tearDown(() async {
    await store.database.close();
    await directory.delete(recursive: true);
  });
  Future<void> flush(WidgetTester tester) async {
    // SQLite runs in a real isolate; alternate real event processing and frames.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'conversation approval saves a restored draft without manual forms or any loaded model',
    (tester) async {
      await tester.pumpWidget(MyApp(store: store, recordService: service));
      await flush(tester);
      expect(find.text('确认记录'), findsOneWidget);
      expect(find.textContaining('支出 CNY 20.00'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '保存');
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      expect(find.text('保存好了。'), findsOneWidget);
      expect(find.text('已保存的记录'), findsOneWidget);
      expect(find.text('已保存'), findsOneWidget);
      expect(find.textContaining('支出 CNY 20.00'), findsOneWidget);
      expect(find.text('确认记录'), findsNothing);
      expect(find.textContaining('批'), findsNothing);
      expect(
        await tester.runAsync(() => repo.all()).then((rows) => rows!.length),
        1,
      );
      await tester.enterText(find.byType(TextField), '同意记录');
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      expect(
        await tester.runAsync(() => repo.all()).then((rows) => rows!.length),
        1,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('interactive refusal never creates a formal record', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(store: store, recordService: service));
    await flush(tester);
    await tester.tap(find.widgetWithText(TextButton, '不记录'));
    await flush(tester);
    expect(await tester.runAsync(() => repo.all()), isEmpty);
    expect(find.text('好的，先不保存。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'a generic yes to another conversation topic cannot approve an older draft',
    (tester) async {
      await tester.pumpWidget(MyApp(store: store, recordService: service));
      await flush(tester);
      store.messages.add({
        'role': 'assistant',
        'text': '需要聊聊别的话题吗？',
        'status': 'done',
        'time': DateTime.now().toIso8601String(),
      });
      await tester.enterText(find.byType(TextField), '好的');
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      expect(await tester.runAsync(() => repo.all()), isEmpty);
      expect(
        (await tester.runAsync(() => repo.proposals()))!.single.status,
        'pending',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'missing reminder time is supplied and approved entirely through dialogue',
    (tester) async {
      await tester.runAsync(() async {
        await repo.decide((await repo.proposals()).single.id, accept: false);
        await repo.propose('reminder', [
          const ExtractedRecord(
            kind: RecordKind.reminder,
            title: '买药',
            quote: '明天提醒我买药',
          ),
        ], context: '明天提醒我买药');
      });
      final scheduler = FakeScheduler();
      final future = DateTime.now().add(const Duration(days: 1));
      service = RecordService(
        repo,
        scheduler,
        (text, now) async => throw StateError('unexpected extraction'),
        refiner: (draft, text, now) async => [
          ExtractedRecord(
            kind: RecordKind.reminder,
            title: '买药',
            quote: '${draft.context}\n$text',
            at: future,
          ),
        ],
      );
      await tester.pumpWidget(MyApp(store: store, recordService: service));
      await flush(tester);
      expect(scheduler.calls, 0);
      await tester.enterText(find.byType(TextField), '明天上午九点');
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      expect(
        (await tester.runAsync(() => repo.proposals()))!.last.missingFields,
        isEmpty,
      );
      expect((await tester.runAsync(() => repo.all()))!.length, 1);
      expect(scheduler.calls, 1);
      expect(find.text('确认记录'), findsNothing);
      await tester.enterText(find.byType(TextField), '同意记录');
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      expect((await tester.runAsync(() => repo.all()))!.length, 1);
      expect(scheduler.calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
