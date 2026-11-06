import 'dart:async';
import 'dart:io';

import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/main.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'message_queue_test.dart' show QueueEngine;
import 'records_test.dart' show FakeScheduler;

void main() {
  late Directory root;
  late LocalStore store;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('auto_record_flow');
    store = await LocalStore.openAt(root);
    store.models['chat'] = {
      'role': 'chat',
      'name': 'test',
      'path': '/test.gguf',
    };
  });
  tearDown(() async {
    await store.database.close();
    await root.delete(recursive: true);
  });
  for (final mode in ['complete', 'missing', 'duplicate']) {
    final complete = mode != 'missing';
    final duplicate = mode == 'duplicate';
    testWidgets(
      duplicate
          ? 'duplicate bill asks again and saves only after renewed confirmation'
          : complete
          ? 'preflight precedes reply and saving follows completion'
          : 'missing facts ask for supplementation after reply',
      (tester) async {
        final repo = RecordRepository(store.database);
        if (duplicate) {
          await tester.runAsync(
            () => repo.insert('already-saved', [
              const ExtractedRecord(
                kind: RecordKind.expense,
                title: '午饭',
                quote: '今天午饭20元',
                amountMinor: 2000,
                currency: 'CNY',
                direction: 'expense',
                date: '2026-11-06',
              ),
            ]),
          );
        }
        final service = RecordService(
          repo,
          FakeScheduler(),
          (text, now) async => [
            ExtractedRecord(
              kind: RecordKind.expense,
              title: '午饭',
              quote: text,
              amountMinor: complete ? 2000 : null,
              currency: 'CNY',
              direction: 'expense',
              date: '2026-11-06',
            ),
          ],
        );
        final engine = QueueEngine();
        Future<void> flush() async {
          for (var i = 0; i < 20; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 15)),
            );
            await tester.pump(const Duration(milliseconds: 30));
          }
        }

        await tester.pumpWidget(
          MyApp(store: store, aiEngine: engine, recordService: service),
        );
        await flush();
        await tester.enterText(
          find.byType(TextField).first,
          complete ? '今天午饭20元' : '今天午饭花了钱',
        );
        await tester.tap(find.byKey(const ValueKey('send-message')));
        await flush();
        final drafts = await tester.runAsync(repo.proposals);
        expect(drafts, hasLength(1));
        expect(
          await tester.runAsync(repo.all),
          duplicate ? hasLength(1) : isEmpty,
        );
        if (complete && !duplicate) {
          expect(engine.prompts.single, contains('应用已检查本轮可记录内容'));
          expect(
            store.messages.where((m) => m['kind'] == 'record_proposal'),
            isEmpty,
          );
          engine.streams.single.add('已了解午饭信息。');
          unawaited(engine.streams.single.close());
          await flush();
        } else {
          expect(engine.prompts, isEmpty);
        }
        if (complete && !duplicate) {
          expect(await tester.runAsync(repo.all), hasLength(1));
          expect(find.text('保存好了。'), findsOneWidget);
          expect(
            store.messages.where((m) => m['kind'] == 'record_proposal'),
            isEmpty,
          );
        } else if (duplicate) {
          expect(
            store.messages.any(
              (m) =>
                  m['kind'] == 'record_proposal' &&
                  (m['text'] as String).contains('可能是同一笔'),
            ),
            isTrue,
          );
          await tester.enterText(find.byType(TextField).first, '确认记录');
          await tester.tap(find.byKey(const ValueKey('send-message')));
          await flush();
          expect(await tester.runAsync(repo.all), hasLength(2));
        } else {
          expect(await tester.runAsync(repo.all), isEmpty);
          expect(
            store.messages.any(
              (m) =>
                  m['kind'] == 'record_proposal' &&
                  (m['text'] as String).contains('金额'),
            ),
            isTrue,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
