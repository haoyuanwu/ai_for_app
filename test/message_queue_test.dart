import 'dart:async';
import 'dart:io';

import 'package:ai_for_app/core/ai_engine.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/main.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:flutter/material.dart';
import 'package:ai_for_app/ui/message_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class QueueEngine extends AiEngine {
  final prompts = <String>[];
  final streams = <StreamController<String>>[];
  @override
  Stream<String> reply(
    LocalStore store,
    String text, {
    String? image,
    void Function(String)? onRelationSaved,
    RecordService? recordService,
    void Function(String)? onMutationError,
  }) {
    prompts.add(text);
    final stream = StreamController<String>();
    streams.add(stream);
    return stream.stream;
  }

  @override
  Future<List<ExtractedRecord>> extract(
    LocalStore store,
    String text,
    DateTime now, {
    String? previousJson,
    ModelRole? role,
  }) async => [];
}

void main() {
  late Directory root;
  late LocalStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp("message_queue");
    store = await LocalStore.openAt(root);
  });
  tearDown(() async {
    await store.database.close();
    await root.delete(recursive: true);
  });
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  testWidgets('queue fits a narrow screen with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 700),
            textScaler: TextScaler.linear(1.5),
          ),
          child: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: Align(
                alignment: Alignment.bottomRight,
                child: MessageQueueView(
                  messages: [
                    QueuedMessage(text: '接下来介绍第二个问题，保留详细说明'),
                    QueuedMessage(text: '请简短一些，用中文回答'),
                    QueuedMessage(text: '', image: '/image.jpg'),
                  ],
                  expanded: true,
                  canGuide: true,
                  onToggle: () {},
                  onGuide: (_) {},
                  onDelete: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'queues FIFO, deletes, guides current reply and preserves draft',
    (tester) async {
      final engine = QueueEngine();
      store.models['chat'] = {
        'id': 'chat',
        'role': 'chat',
        'name': 'test',
        'path': '/test.gguf',
        'format': 'gguf',
      };
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      Future<void> flush() async {
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump(const Duration(milliseconds: 30));
        }
      }

      Future<void> send(String text) async {
        await tester.enterText(find.byType(TextField).first, text);
        await tester.tap(find.byKey(const ValueKey('send-message')));
        await flush();
      }

      await tester.pumpWidget(MyApp(store: store, aiEngine: engine));
      await flush();
      await send('请介绍一下植物');
      expect(engine.prompts, hasLength(1));
      engine.streams.first.add('植物');
      await tester.pump();
      await send('第二个问题');
      await send('不要发送这条');
      await send('请简短一些');
      expect(engine.prompts, hasLength(1));
      expect(find.text('待发送 3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('message-queue-toggle')));
      await tester.pump();
      final deleteRow = find
          .ancestor(of: find.text('不要发送这条'), matching: find.byType(Row))
          .first;
      await tester.tap(
        find.descendant(of: deleteRow, matching: find.byTooltip('删除排队消息')),
      );
      await tester.pump();
      final guideRow = find
          .ancestor(of: find.text('请简短一些'), matching: find.byType(Row))
          .first;
      await tester.tap(
        find.descendant(of: guideRow, matching: find.text('引导')),
      );
      engine.streams.first.add('边界');
      await flush();
      expect(engine.prompts, hasLength(2));
      expect(engine.prompts.last, contains('请简短一些'));
      expect(find.text('待发送 1'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '还没发出的草稿');
      engine.streams[1].add('简短回复');
      unawaited(engine.streams[1].close());
      await flush();
      expect(engine.prompts, hasLength(3));
      expect(engine.prompts.last, contains('第二个问题'));
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '还没发出的草稿',
      );
      engine.streams.last.add('队列回复');
      unawaited(engine.streams.last.close());
      await flush();
      expect(find.byKey(const ValueKey('message-queue-toggle')), findsNothing);
      expect(engine.prompts.any((p) => p.contains('不要发送这条')), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
