import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/core/assistant_persona.dart';
import 'package:ai_for_app/core/ai_engine.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/core/conversation_messages.dart';
import 'package:ai_for_app/main.dart';
import 'package:nobodywho/nobodywho.dart' as nw;

void main() {
  test('common naming requests persist names without model extraction', () {
    for (final text in [
      '你就叫小白',
      '你今后叫小白',
      '给你取个名字叫小白',
      '给你起一个名字：小白',
      '就叫小白',
      '叫你小白',
    ]) {
      expect(AssistantPersona.parse(text), {'name': '小白'}, reason: text);
    }
    for (final text in ['你是谁？', '还记得我给你起的名字吗？', '我叫小白', '给他取个名字叫小白']) {
      expect(AssistantPersona.isRequest(text), isFalse, reason: text);
    }
  });

  test(
    'identity comes from current settings without loading a model',
    () async {
      final store = LocalStore(Directory.systemTemp);
      store.data['assistantPersona'] = {'name': '小白'};
      expect(await AiEngine().reply(store, '你叫什么名字？').join(), '我叫小白，是你的私人助理。');
      store.data['assistantPersona'] = {'name': '小蓝'};
      expect(await AiEngine().reply(store, '你是谁？').join(), '我叫小蓝，是你的私人助理。');
      for (final text in ['你是什么模型？', '你是谁？顺便帮我查记录', '我叫什么名字？', '如果你叫小白会怎样']) {
        expect(
          AssistantPersona.identityReply(text, AssistantPersona.defaults),
          isNull,
        );
      }
    },
  );

  test(
    'default and conversational changes distinguish assistant from user',
    () {
      expect(AssistantPersona.read({})['personality'], '开朗、礼貌、严谨、干练');
      expect(AssistantPersona.parse('以后你叫小白，性格改为温柔，喜欢音乐，说话简短一点'), {
        'name': '小白',
        'personality': '温柔',
        'interests': '音乐',
        'style': '简短一点',
      });
      for (final text in [
        '我喜欢音乐',
        '你的兴趣是什么',
        '你叫我小明',
        '你的名字是什么',
        '你喜欢什么？',
        '如果你叫小白会怎样',
      ]) {
        expect(AssistantPersona.isRequest(text), isFalse);
      }
      expect(AssistantPersona.parse('以后你叫小白，我喜欢音乐'), {'name': '小白'});
      expect(AssistantPersona.parse('恢复默认人格'), AssistantPersona.defaults);
    },
  );
  test('active persona is injected without replaying old persona commands', () {
    final messages = conversationMessages(
      [
        {
          'role': 'user',
          'text': '旧的人格设定',
          'kind': 'persona_update',
          'status': 'done',
        },
      ],
      '你好',
      retrieved: '{}',
      now: DateTime(2026),
      persona: {...AssistantPersona.defaults, 'name': '小白', 'style': '简洁'},
    );
    expect(messages.length, 2);
    expect((messages.first as nw.Message_System).content.text, contains('小白'));
    expect(
      (messages.first as nw.Message_System).content.text,
      contains('私人助理'),
    );
  });
  testWidgets(
    'persona edits save through chat without a model and survive reopening',
    (tester) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      late Directory root;
      late LocalStore store;
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('persona');
        store = await LocalStore.openAt(root);
      });
      try {
        await tester.pumpWidget(MyApp(store: store));
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
        await tester.enterText(
          find.byType(TextField),
          '以后你叫小白，性格改为温柔，喜欢音乐，说话简短一点',
        );
        await tester.tap(find.byTooltip('发送'));
        await flush();
        expect(AssistantPersona.read(store.data)['name'], '小白');
        expect(find.textContaining('已更新：'), findsNothing);
        expect(store.messages.where((m) => m['role'] == 'assistant'), isEmpty);
        expect(
          await tester.runAsync(() => store.database.query('records')),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await store.database.close();
          store = await LocalStore.openAt(root);
        });
        expect(AssistantPersona.read(store.data)['interests'], '音乐');
        await tester.pumpWidget(MyApp(store: store));
        await flush();
        await tester.enterText(find.byType(TextField), '你叫什么名字？');
        await tester.tap(find.byTooltip('发送'));
        await flush();
        expect(find.textContaining('我叫小白，是你的私人助理。'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        await tester.runAsync(() async {
          await store.database.close();
          await root.delete(recursive: true);
        });
      }
    },
  );
}
