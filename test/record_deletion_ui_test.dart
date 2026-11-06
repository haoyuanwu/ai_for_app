import 'dart:io';

import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:ai_for_app/ui/records_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'records_test.dart' show FakeScheduler;

void main() {
  late Directory directory;
  late LocalStore store;
  late RecordRepository repository;
  late FakeScheduler scheduler;
  late RecordService service;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('record_delete');
    store = await LocalStore.openAt(directory);
    repository = RecordRepository(store.database);
    scheduler = FakeScheduler();
    service = RecordService(repository, scheduler, (text, now) async => []);
  });
  tearDown(() async {
    await store.database.close();
    await directory.delete(recursive: true);
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

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordsView(store: store, service: service),
        ),
      ),
    );
    await flush(tester);
  }

  testWidgets('deletion requires confirmation, cancels reminder and persists', (
    tester,
  ) async {
    await tester.runAsync(
      () => repository.insert('reminder', [
        ExtractedRecord(
          kind: RecordKind.reminder,
          title: '开会',
          quote: '提醒开会',
          at: DateTime.now().add(const Duration(days: 1)),
        ),
      ]),
    );
    final rows = await tester.runAsync(repository.all);
    final id = rows!.single['id'] as int;
    await tester.runAsync(() => service.schedule(id));
    await show(tester);
    await tester.ensureVisible(find.byTooltip('删除记录'));
    await tester.tap(find.byTooltip('删除记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留'));
    await tester.pumpAndSettle();
    expect((await tester.runAsync(repository.all))!.length, 1);
    expect(scheduler.requests, contains(id));
    await tester.tap(find.byTooltip('删除记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await flush(tester);
    expect(await tester.runAsync(repository.all), isEmpty);
    expect(scheduler.requests, isEmpty);
    expect(find.byTooltip('删除记录'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await store.database.close();
      store = await LocalStore.openAt(directory);
      expect(await RecordRepository(store.database).all(), isEmpty);
    });
  });
  testWidgets(
    'legacy saved note deletion persists without changing chat history',
    (tester) async {
      store.messages.add({'role': 'user', 'text': '保留聊天'});
      store.notes.add({
        'text': '旧收藏',
        'category': '事项',
        'savedAt': '2026-11-04',
      });
      await tester.runAsync(store.save);
      await show(tester);
      await tester.ensureVisible(find.byTooltip('删除收藏'));
      await tester.tap(find.byTooltip('删除收藏'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await flush(tester);
      expect(store.notes, isEmpty);
      expect(find.text('旧收藏'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await store.database.close();
        store = await LocalStore.openAt(directory);
        expect(store.notes, isEmpty);
        expect(store.messages.single['text'], '保留聊天');
      });
    },
  );
}
