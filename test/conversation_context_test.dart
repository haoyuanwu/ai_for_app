import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/core/conversation_context.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test('summaries checkpoint old messages, survive reopening and retain original history', () async {
    final dir = await Directory.systemTemp.createTemp('context_test');
    var store = await LocalStore.openAt(dir);
    try {
      store.messages.addAll(
        List.generate(
          16,
          (i) => {
            'role': i.isEven ? 'user' : 'assistant',
            'status': 'done',
            'text': '第$i轮${List.filled(300, '事实').join()}',
          },
        ),
      );
      var calls = 0;
      await ConversationContext.prepare(
        store,
        '继续',
        summarize: (old, transcript) async {
          calls++;
          return '用户正在整理资料；原始事实可查历史。';
        },
      );
      expect(calls, greaterThan(0));
      expect(ConversationContext.cutoff(store), greaterThan(0));
      expect(store.messages.length, 16);
      expect(
        ConversationContext.history(store).length,
        greaterThanOrEqualTo(2),
      );
      expect(
        ConversationContext.usage(store, '继续'),
        lessThan(ConversationContext.window),
      );
      await store.database.close();
      store = await LocalStore.openAt(dir);
      expect(ConversationContext.summary(store), contains('整理资料'));
      expect(store.messages.length, 16);
    } finally {
      await store.database.close();
      await dir.delete(recursive: true);
    }
  });
  test(
    'failed summary does not advance checkpoint or delete history',
    () async {
      final dir = await Directory.systemTemp.createTemp('context_failure');
      final store = await LocalStore.openAt(dir);
      try {
        store.messages.addAll(
          List.generate(
            10,
            (i) => {
              'role': 'user',
              'status': 'done',
              'text': List.filled(2000, '长').join(),
            },
          ),
        );
        await expectLater(
          ConversationContext.prepare(
            store,
            '',
            summarize: (_, _) async => throw StateError('failed'),
          ),
          throwsStateError,
        );
        expect(ConversationContext.cutoff(store), 0);
        expect(store.messages.length, 10);
      } finally {
        await store.database.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'token estimate counts Unicode safely and includes image/reply budget',
    () {
      final store = LocalStore(Directory.systemTemp);
      expect(
        ConversationContext.usage(store, 'abc', image: true) -
            ConversationContext.usage(store, 'abc'),
        ConversationContext.imageReserve,
      );
      final clipped = ConversationContext.clip('甲😀乙', 3);
      expect(clipped.runes.toList(), [0x7532]);
    },
  );
}
