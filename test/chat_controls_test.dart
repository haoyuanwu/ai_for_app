import 'dart:io';

import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/main.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';

import 'records_test.dart' show FakeScheduler;

import 'package:ai_for_app/ui/app_theme.dart';
import 'package:ai_for_app/ui/error_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory root;
  late LocalStore store;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('chat_controls');
    store = await LocalStore.openAt(root);
  });
  tearDown(() async {
    await store.database.close();
    await root.delete(recursive: true);
  });
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
  }

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MyApp(store: store));
    await flush(tester);
  }

  testWidgets('chat hides organize actions for old and failed messages', (
    tester,
  ) async {
    store.messages.addAll([
      {'role': 'user', 'text': '旧消息', 'status': 'done'},
      {
        'role': 'user',
        'text': '尚未保存的内容',
        'status': 'done',
        'extraction': 'failed',
      },
    ]);
    await show(tester);
    expect(find.text('自动整理'), findsNothing);
    expect(find.text('重试自动整理'), findsNothing);
    expect(find.text('旧消息'), findsOneWidget);
    expect(find.text('尚未保存的内容'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'opens at latest message and loads older history in pages of 50',
    (tester) async {
      store.messages.addAll(
        List.generate(
          125,
          (index) => {'role': 'user', 'text': '历史消息 $index', 'status': 'done'},
        ),
      );
      await show(tester);
      ListView list() => tester.widget<ListView>(find.byType(ListView).first);
      int count() =>
          (list().childrenDelegate as SliverChildBuilderDelegate).childCount!;
      expect(list().reverse, isTrue);
      expect(count(), 50);
      expect(list().controller!.offset, 0);
      expect(find.text('历史消息 124'), findsOneWidget);

      final controller = list().controller!;
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(count(), 100);
      final offset = controller.offset;
      await tester.pump();
      expect(controller.offset, offset);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(count(), 125);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(count(), 125);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('message pages have stable boundaries when new messages arrive', () {
    store.messages.addAll(List.generate(125, (index) => {'text': '$index'}));
    expect(store.messagePage().length, 50);
    expect(store.messagePage().first['text'], '75');
    store.messages.add({'text': '125'});
    final older = store.messagePage(before: 75);
    expect(older.length, 50);
    expect(older.first['text'], '25');
    expect(older.last['text'], '74');
    expect(store.messagePage(before: 25).length, 25);
    expect(store.messagePage(before: 0), isEmpty);
  });

  testWidgets('error floats at top and remains until manually closed', (
    tester,
  ) async {
    await show(tester);
    await tester.enterText(find.byType(TextField), '待发送草稿');
    await tester.tap(find.byTooltip('发送'));
    await flush(tester);
    expect(find.byType(ErrorNotice), findsOneWidget);
    expect(tester.getTopLeft(find.byType(ErrorNotice)).dy, lessThan(100));
    await tester.pump(const Duration(seconds: 30));
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorNotice), findsOneWidget);
    expect(find.text('待发送草稿'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭错误通知'));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorNotice), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('failed generation retains user turn as completed history', (
    tester,
  ) async {
    store.models['missing'] = {
      'name': 'Qwen3.5',
      'path': '${root.path}/missing.gguf',
      'format': 'gguf',
      'capabilities': ['chat'],
    };
    store.selected['chat'] = 'missing';
    await show(tester);
    await tester.enterText(find.byType(TextField), '我叫小明');
    await tester.tap(find.byTooltip('发送'));
    await flush(tester);
    expect(store.messages.first['status'], 'done');
    expect(store.messages.last['status'], 'failed');
    expect(find.byType(ErrorNotice), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'explicit complete request produces a receipt without another confirmation',
    (tester) async {
      store.models['chat'] = {
        'name': 'local',
        'path': '/not-loaded.gguf',
        'format': 'gguf',
        'capabilities': ['chat'],
      };
      store.selected['chat'] = 'chat';
      final service = RecordService(
        RecordRepository(store.database),
        FakeScheduler(),
        (text, now) async => [
          const ExtractedRecord(
            kind: RecordKind.expense,
            title: '午饭',
            quote: '午饭20元',
            amountMinor: 2000,
            currency: 'CNY',
            direction: 'expense',
          ),
        ],
      );
      await tester.pumpWidget(MyApp(store: store, recordService: service));
      await flush(tester);
      await tester.enterText(find.byType(TextField), '帮我记一下，午饭20元');
      await tester.tap(find.byTooltip('发送'));
      await flush(tester);
      expect(find.text('保存好了。'), findsOneWidget);
      expect(find.text('确认记录'), findsNothing);
      expect(
        store.messages.any((m) => (m['text'] as String).contains('是否记录')),
        isFalse,
      );
      expect((await tester.runAsync(service.repository.all))!.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('composer has no manual model picker', (tester) async {
    store.models['a'] = {
      'name': 'Qwen3.5 0.8B',
      'capabilities': ['chat', 'vision'],
    };
    store.selected.addAll({'chat': 'a', 'vision': 'a'});
    await show(tester);
    expect(find.byKey(const ValueKey('conversation-model')), findsNothing);
    expect(find.text('Qwen3.5 0.8B'), findsNothing);
    expect(find.byTooltip('发送'), findsOneWidget);
    expect(store.selected, {'chat': 'a', 'vision': 'a'});
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'blank taps and dragging messages dismiss editing and retain draft',
    (tester) async {
      await show(tester);
      await tester.enterText(find.byType(TextField), '保留文字');
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.tapAt(const Offset(20, 200));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.text('保留文字'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      store.messages.addAll(
        List.generate(
          20,
          (i) => {
            'role': 'user',
            'text': '历史消息 $i',
            'status': 'done',
            'extraction': 'done',
          },
        ),
      );
      await tester.pumpWidget(MyApp(store: store));
      await flush(tester);
      await tester.enterText(find.byType(TextField), '新的草稿');
      await tester.drag(find.byType(ListView).first, const Offset(0, 150));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.text('新的草稿'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'long notices scroll with large text and maintain readable contrast',
    (tester) async {
      final scheme = journalTheme().colorScheme;
      final contrast =
          (scheme.errorContainer.computeLuminance() + .05) /
          (scheme.onErrorContainer.computeLuminance() + .05);
      expect(contrast, greaterThanOrEqualTo(4.5));
      await tester.pumpWidget(
        MaterialApp(
          theme: journalTheme(),
          home: Scaffold(
            body: Center(
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
                child: SizedBox(
                  width: 343,
                  height: 200,
                  child: ErrorNotice(
                    message: '模型加载失败，请检查文件。' * 100,
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('关闭错误通知'), findsOneWidget);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
