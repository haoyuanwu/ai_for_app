import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/main.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:ai_for_app/ui/message_reference_view.dart';

import 'vision_routing_test.dart' show VisionEngine;

class ReferenceEngine extends VisionEngine {
  String? prompt;
  int transcriptions = 0;
  @override
  Stream<String> reply(
    LocalStore store,
    String text, {
    String? image,
    void Function(String)? onRelationSaved,
    RecordService? recordService,
    void Function(String)? onMutationError,
  }) async* {
    prompt = text;
    lastImage = image;
    yield '已针对引用内容回答';
  }

  @override
  Future<String> transcribe(LocalStore store, String audio) async {
    transcriptions++;
    return '引用音频的识别内容';
  }
}

void main() {
  late Directory dir;
  late LocalStore store;
  late ReferenceEngine engine;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('reference_test');
    store = await LocalStore.openAt(dir);
    engine = ReferenceEngine();
    store.models.addAll({
      'chat': {
        'name': 'chat',
        'path': 'unused',
        'capabilities': ['chat'],
      },
      'vision': {
        'name': 'vision',
        'path': 'unused',
        'capabilities': ['vision'],
      },
    });
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

  Future<void> show(WidgetTester t) async {
    await t.pumpWidget(MyApp(store: store, aiEngine: engine));
    await flush(t);
  }

  Future<void> quote(WidgetTester t, Finder target) async {
    await t.longPress(target);
    await t.pumpAndSettle();
    await t.tap(find.text('引用'));
    await flush(t);
    expect(find.byKey(const ValueKey('composer-reference')), findsOneWidget);
  }

  testWidgets(
    'quote text previews one line, sends only new text and targets original content',
    (t) async {
      store.messages.add({
        'id': 'source',
        'role': 'user',
        'text': '第一行原文\n第二行原文',
        'status': 'done',
        'extraction': 'done',
      });
      await show(t);
      await quote(t, find.text('第一行原文\n第二行原文'));
      final oneLine = t
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('composer-reference')),
              matching: find.byType(Text),
            ),
          )
          .last;
      expect(oneLine.maxLines, 1);
      await t.enterText(find.byType(TextField), '解释一下');
      await t.tap(find.byTooltip('发送'));
      await flush(t);
      final sent = store.messages.lastWhere((m) => m['role'] == 'user');
      expect(sent['text'], '解释一下');
      expect(sent['replyTo'], 'source');
      expect(sent['image'], isNull);
      expect(sent['audio'], isNull);
      expect(engine.prompt, contains('第一行原文\n第二行原文'));
      expect(find.byKey(const ValueKey('composer-reference')), findsNothing);
      expect(find.byType(MessageReferenceView), findsOneWidget);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'quote image uses a compact reference without attaching a second image',
    (t) async {
      final file = File('${dir.path}/photo.png');
      await t.runAsync(
        () => file.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9XkAAAAASUVORK5CYII=',
          ),
        ),
      );
      store.messages.add({
        'id': 'photo',
        'role': 'user',
        'text': '原图',
        'image': file.path,
        'status': 'done',
        'extraction': 'done',
        'recognizedTextSource': 'image',
        'recognizedText': '张三电话13800138000',
      });
      await show(t);
      await quote(t, find.text('原图'));
      expect(
        find.byKey(const ValueKey('composer-image-preview')),
        findsNothing,
      );
      await t.enterText(find.byType(TextField), '解释这个内容');
      await t.tap(find.byTooltip('发送'));
      await flush(t);
      final sent = store.messages.lastWhere((m) => m['role'] == 'user');
      expect(sent['replyTo'], 'photo');
      expect(sent['image'], isNull);
      final view = t.widget<MessageReferenceView>(
        find.byType(MessageReferenceView),
      );
      expect(view.draft, isFalse);
      expect(view.source!['image'], file.path);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'quote audio transcribes source without sending it as new audio',
    (t) async {
      store.messages.add({
        'id': 'audio',
        'role': 'user',
        'text': '录音来源',
        'audio': '${dir.path}/audio.wav',
        'status': 'done',
        'extraction': 'done',
      });
      await show(t);
      await quote(t, find.text('录音来源'));
      expect(engine.transcriptions, 0);
      await t.enterText(find.byType(TextField), '总结这段音频');
      await t.tap(find.byTooltip('发送'));
      await flush(t);
      final sent = store.messages.lastWhere((m) => m['role'] == 'user');
      expect(sent['replyTo'], 'audio');
      expect(sent['audio'], isNull);
      expect(engine.prompt, contains('引用音频的识别内容'));
      expect(engine.transcriptions, 1);
      await quote(t, find.text('录音来源'));
      await t.enterText(find.byType(TextField), '再总结一次');
      await t.tap(find.byTooltip('发送'));
      await flush(t);
      expect(engine.transcriptions, 1);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('saving a quoted proposal only approves that proposal', (
    t,
  ) async {
    final repo = RecordRepository(store.database);
    await t.runAsync(() async {
      for (final amount in [2000, 3000]) {
        await repo.propose('source-$amount', [
          ExtractedRecord(
            kind: RecordKind.expense,
            title: '消费$amount',
            quote: '消费${amount ~/ 100}元',
            amountMinor: amount,
            currency: 'CNY',
            direction: 'expense',
          ),
        ]);
      }
    });
    await show(t);
    await quote(t, find.text('支出 CNY 20.00'));
    await t.enterText(find.byType(TextField), '保存');
    await t.tap(find.byTooltip('发送'));
    await flush(t);
    final rows = (await t.runAsync(() => repo.all()))!;
    expect(rows, hasLength(1));
    expect(jsonDecode(rows.single['payload'] as String)['amountMinor'], 2000);
    final drafts = (await t.runAsync(() => repo.proposals()))!;
    expect(drafts.where((p) => p.status == 'pending'), hasLength(1));
    expect(store.messages.where((m) => m['replyTo'] != null), hasLength(1));
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('tap reference loads an older page and highlights the source', (
    t,
  ) async {
    store.messages.addAll(
      List.generate(
        80,
        (i) => {
          'id': 'msg$i',
          'role': 'user',
          'text': '历史消息 $i',
          'status': 'done',
          'extraction': 'done',
        },
      ),
    );
    store.messages.add({
      'id': 'new',
      'role': 'user',
      'text': '针对第一条',
      'replyTo': 'msg0',
      'status': 'done',
      'extraction': 'done',
    });
    await show(t);
    expect(
      find.textContaining('历史消息 0'),
      findsOneWidget,
    ); // reference preview only
    await t.tap(find.byType(MessageReferenceView));
    for (var i = 0; i < 150; i++) {
      await t.pump(const Duration(milliseconds: 20));
      if (find
          .widgetWithText(AnimatedContainer, '历史消息 0')
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }
    await t.pump(const Duration(milliseconds: 300));
    final sources = find.widgetWithText(AnimatedContainer, '历史消息 0');
    expect(sources, findsOneWidget);
    expect(
      t.widget<AnimatedContainer>(sources).foregroundDecoration,
      isNotNull,
    );
    expect(
      t.getRect(sources).overlaps(t.getRect(find.byType(ListView).first)),
      isTrue,
    );
    await t.pump(const Duration(seconds: 3));
    expect(t.widget<AnimatedContainer>(sources).foregroundDecoration, isNull);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
