import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ai_for_app/main.dart';
import 'package:ai_for_app/core/ai_engine.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/records/record_deletion.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:ai_for_app/records/extracted_record.dart';

import 'records_test.dart' show FakeScheduler;

class LyingEngine extends AiEngine {
  @override
  Stream<String> reply(
    LocalStore store,
    String text, {
    String? image,
    void Function(String)? onRelationSaved,
    RecordService? recordService,
    void Function(String)? onMutationError,
  }) async* {
    yield '已清理所有记录';
  }
}

void main() {
  late Directory root;
  late LocalStore store;
  late RecordRepository repo;
  late RecordService service;
  late FakeScheduler scheduler;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('chat_delete');
    store = await LocalStore.openAt(root);
    repo = RecordRepository(store.database);
    scheduler = FakeScheduler();
    service = RecordService(repo, scheduler, (text, now) async => []);
    await repo.insert('original', [
      const ExtractedRecord(
        kind: RecordKind.expense,
        title: '午饭',
        quote: '午饭20元',
        amountMinor: 2000,
        currency: 'CNY',
        direction: 'expense',
      ),
      ExtractedRecord(
        kind: RecordKind.reminder,
        title: '买药',
        quote: '提醒买药',
        at: DateTime.now().add(const Duration(days: 1)),
      ),
    ]);
  });
  tearDown(() async {
    await store.database.close();
    await root.delete(recursive: true);
  });
  testWidgets(
    'model claiming deletion without executing is never shown as success',
    (tester) async {
      store.models['chat'] = {
        'name': 'fake',
        'path': '/unused',
        'capabilities': ['chat'],
      };
      store.selected['chat'] = 'chat';
      await tester.pumpWidget(
        MyApp(store: store, recordService: service, aiEngine: LyingEngine()),
      );
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
      await tester.enterText(find.byType(TextField), '删除午饭记录');
      await tester.tap(find.byTooltip('发送'));
      await flush();
      expect(find.text('已清理所有记录'), findsNothing);
      expect(find.textContaining('待删除记录 #'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '确认删除'), findsOneWidget);
      expect((await tester.runAsync(repo.all))!.length, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'reviewed deletion can be confirmed by button after restart without loading model',
    (tester) async {
      final id =
          (await tester.runAsync(repo.all))!
                  .singleWhere((r) => r['kind'] == 'expense')['id']
              as int;
      final deletion = RecordDeletion(store, '删除午饭记录', service);
      String? question;
      await tester.runAsync(() async {
        await deletion.page('records', '午饭', 0);
        final result = jsonDecode(await deletion.delete(id)) as Map;
        question = result['question'] as String;
        store.messages.add({
          'role': 'assistant',
          'text': question,
          'status': 'done',
          'kind': 'deletion_proposal',
          'deletionToken': (store.data['pendingDeletion'] as Map)['token'],
        });
        await store.save();
        await store.database.close();
        store = await LocalStore.openAt(root);
      });
      repo = RecordRepository(store.database);
      service = RecordService(repo, scheduler, (t, n) async => []);
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
      expect((await tester.runAsync(repo.all))!.length, 2);
      expect(find.text(question!), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '确认删除'));
      await flush();
      expect((await tester.runAsync(repo.all))!.length, 1);
      expect(find.textContaining('已删除“午饭”'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '确认删除'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'only an actual unique deletion emits success and removes old associations',
    () async {
      final rows = await repo.all();
      final id = rows.singleWhere((r) => r['kind'] == 'expense')['id'] as int;
      final other =
          rows.singleWhere((r) => r['kind'] == 'reminder')['id'] as int;
      await repo.link(id, other);
      final receipts = <String>[];
      final deletion = RecordDeletion(
        store,
        '删除午饭记录',
        service,
        onPreview: receipts.add,
      );
      expect(jsonDecode(await deletion.delete(id))['deleted'], isFalse);
      expect(receipts, isEmpty);
      await deletion.page('records', '买药', 0);
      expect(jsonDecode(await deletion.delete(other))['deleted'], isFalse);
      await deletion.page('records', '午饭', 0);
      expect(
        jsonDecode(await deletion.delete(id))['pendingConfirmation'],
        isTrue,
      );
      expect((await repo.all()).length, 2);
      store.messages.add({
        'role': 'assistant',
        'kind': 'deletion_proposal',
        'deletionToken': (store.data['pendingDeletion'] as Map)['token'],
      });
      expect(
        await RecordDeletion.respond(store, service, '确认删除第$id条'),
        contains('已删除'),
      );
      expect(receipts.single, contains('确认删除吗'));
      expect((await repo.all()).length, 1);
      expect(
        jsonDecode(
          (await repo.get(other))['payload'] as String,
        )['relatedRecordIds'],
        isEmpty,
      );
      expect(await RecordDeletion.respond(store, service, '确认删除第$id条'), isNull);
      expect(receipts.length, 1);
    },
  );
  test(
    'notification failure never reports deletion success and retains record',
    () async {
      final id =
          (await repo.all()).singleWhere((r) => r['kind'] == 'reminder')['id']
              as int;
      await service.schedule(id);
      scheduler.failCancel = true;
      final success = <String>[], errors = <String>[];
      final deletion = RecordDeletion(
        store,
        '删除买药提醒',
        service,
        onPreview: success.add,
        onFailed: errors.add,
      );
      await deletion.page('records', '买药', 0);
      expect(jsonDecode(await deletion.delete(id))['deleted'], isFalse);
      expect(success.single, contains('确认删除吗'));
      expect(errors, isEmpty);
      store.messages.add({
        'role': 'assistant',
        'kind': 'deletion_proposal',
        'deletionToken': (store.data['pendingDeletion'] as Map)['token'],
      });
      expect(
        await RecordDeletion.respond(store, service, '确认删除'),
        contains('记录仍保留'),
      );
      expect((await repo.get(id))['status'], 'cancel_failed');
      expect((await repo.all()).length, 2);
    },
  );
  test('deletion can be cancelled and stale confirmations cannot delete edited content', () async {
    final id = (await repo.all()).first['id'] as int;
    final row = await repo.get(id);
    final title =
        (jsonDecode(row['payload'] as String) as Map)['title'] as String;
    final deletion = RecordDeletion(store, '删除$title', service);
    await deletion.page('records', title, 0);
    await deletion.delete(id);
    expect(await RecordDeletion.respond(store, service, '确认删除第$id条'), isNull);
    store.messages.add({
      'role': 'assistant',
      'kind': 'deletion_proposal',
      'deletionToken': (store.data['pendingDeletion'] as Map)['token'],
    });
    expect(
      await RecordDeletion.respond(store, service, '取消删除'),
      contains('已取消'),
    );
    expect((await repo.all()).length, 2);
    await deletion.delete(id);
    store.messages.add({
      'role': 'assistant',
      'kind': 'deletion_proposal',
      'deletionToken': (store.data['pendingDeletion'] as Map)['token'],
    });
    await service.edit(id, {'title': '修改后的标题'});
    expect(
      await RecordDeletion.respond(store, service, '确认删除'),
      contains('内容已变化'),
    );
    expect((await repo.all()).length, 2);
  });
  test(
    'questions, negative commands and ambiguous queries cannot delete',
    () async {
      for (final text in ['不要删除午饭', '如何删除记录？', '如果删除记录']) {
        expect(RecordDeletion.requested(text), isFalse);
      }
      await repo.insert('another', [
        const ExtractedRecord(
          kind: RecordKind.task,
          title: '午饭计划',
          quote: '午饭计划',
        ),
      ]);
      final id = (await repo.all()).first['id'] as int;
      final deletion = RecordDeletion(store, '删除午饭', service);
      await deletion.page('records', '午饭', 0);
      expect(jsonDecode(await deletion.delete(id))['deleted'], isFalse);
      expect((await repo.all()).length, 3);
    },
  );
}
