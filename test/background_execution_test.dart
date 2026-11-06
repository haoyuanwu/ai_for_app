import 'dart:async';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/core/local_store.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_for_app/core/background_execution.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'nested inference holds one platform grant until every operation finishes',
    () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(BackgroundExecution.channel, (call) async {
            calls.add(call.method);
            return null;
          });
      final first = await BackgroundExecution.acquire();
      final second = await BackgroundExecution.acquire();
      expect(calls, ['begin']);
      await first();
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['begin']);
      await second();
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['begin', 'end']);
      await second();
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['begin', 'end']);
    },
  );
  test('expiration pauses new decoding until foreground resume and always releases after failure', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackgroundExecution.channel, (call) async {
          calls.add(call.method);
          return null;
        });
    Future<void> event(String name) async {
      final done = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            BackgroundExecution.channel.name,
            const StandardMethodCodec().encodeMethodCall(MethodCall(name)),
            (_) => done.complete(),
          );
      await done.future;
    }

    final release = await BackgroundExecution.acquire();
    await event('expired');
    var passed = false;
    final wait = BackgroundExecution.waitUntilAllowed().then((_) {
      passed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(passed, false);
    expect(BackgroundExecution.status.value, contains('已保留进度'));
    await event('resumed');
    await wait;
    expect(passed, true);
    expect(BackgroundExecution.status.value, isNull);
    await release();
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      BackgroundExecution.run(() async => throw StateError('failure')),
      throwsStateError,
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['begin', 'end', 'begin', 'end']);
  });
  test('OS process interruption preserves partial reply and does not mark it completed', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('background_checkpoint');
    var store = await LocalStore.openAt(dir);
    try {
      store.messages.addAll([
        {'role': 'user', 'text': '继续分析', 'status': 'pending'},
        {'role': 'assistant', 'text': '已经生成的部分内容', 'status': 'pending'},
      ]);
      await store.save();
      await store.database.close();
      store = await LocalStore.openAt(dir);
      expect(store.messages.last['text'], '已经生成的部分内容');
      expect(store.messages.last['status'], 'failed');
      expect(store.messages.last['interrupted'], true);
      expect(await store.database.query('records'), isEmpty);
    } finally {
      await store.database.close();
      await dir.delete(recursive: true);
    }
  });
}
