import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/main.dart';
import 'package:ai_for_app/core/ai_engine.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:ai_for_app/records/extracted_record.dart';

import 'records_test.dart' show FakeScheduler;

class ToolEngine extends AiEngine {
  String action = 'open';
  Map<String, dynamic> args = {'page': 'settings'};
  Map? result;
  @override
  Stream<String> reply(
    LocalStore store,
    String text, {
    String? image,
    void Function(String)? onRelationSaved,
    RecordService? recordService,
    void Function(String)? onMutationError,
  }) async* {
    result = jsonDecode(
      await appActions!.run(
        action,
        jsonEncode(args),
        request:
            store.messages.lastWhere((m) => m['role'] == 'user')['text']
                as String,
      ),
    );
    yield '操作回执：${result!['status'] ?? result!['deletedCount']}';
  }
}

void main() {
  late Directory dir;
  late LocalStore store;
  late RecordService service;
  late ToolEngine engine;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('app_action_ui');
    store = await LocalStore.openAt(dir);
    store.models['chat'] = {
      'name': 'test',
      'path': 'unused',
      'capabilities': ['chat'],
    };
    service = RecordService(
      RecordRepository(store.database),
      FakeScheduler(),
      (_, _) async => [],
    );
    engine = ToolEngine();
  });
  tearDown(() async {
    await store.database.close();
    await dir.delete(recursive: true);
  });
  Future<void> flush(WidgetTester t) async {
    for (var i = 0; i < 15; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 20));
    }
    await t.pumpAndSettle();
  }

  testWidgets('model tool actually opens settings and returns to chat', (
    t,
  ) async {
    await t.pumpWidget(
      MyApp(store: store, aiEngine: engine, recordService: service),
    );
    await flush(t);
    await t.enterText(find.byType(TextField), '打开设置');
    await t.tap(find.byTooltip('发送'));
    await flush(t);
    expect(engine.result!['status'], 'opened');
    expect(find.text('语音录入转写'), findsOneWidget);
    await t.pageBack();
    await flush(t);
    expect(find.textContaining('操作回执：opened'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    expect(engine.appActions, isNull);
  });
  testWidgets(
    'clear command opens confirmation, cancel keeps rows and explicit confirm deletes',
    (t) async {
      await t.runAsync(() async {
        await service.repository.propose('expense', [
          const ExtractedRecord(
            kind: RecordKind.expense,
            title: '午饭',
            quote: '午饭20元',
            amountMinor: 2000,
            currency: 'CNY',
            direction: 'expense',
          ),
        ]);
        await service.decide(
          (await service.repository.proposals()).single.id,
          accept: true,
        );
      });
      engine
        ..action = 'clear_records'
        ..args = {};
      await t.pumpWidget(
        MyApp(store: store, aiEngine: engine, recordService: service),
      );
      await flush(t);
      await t.enterText(find.byType(TextField), '清空记录');
      await t.tap(find.byTooltip('发送'));
      await flush(t);
      expect(find.text('清空正式记录'), findsOneWidget);
      expect(await t.runAsync(() => service.repository.all()), hasLength(1));
      await t.tap(find.widgetWithText(TextButton, '取消'));
      await flush(t);
      expect(engine.result!['status'], 'cancelled');
      await t.enterText(find.byType(TextField), '清空记录');
      await t.tap(find.byTooltip('发送'));
      await flush(t);
      await t.tap(find.text('确认操作'));
      await flush(t);
      expect(await t.runAsync(() => service.repository.all()), isEmpty);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
