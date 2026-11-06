import 'dart:async';
import 'dart:io';

import 'package:ai_for_app/core/ai_engine.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/core/native_speech.dart';
import 'package:ai_for_app/core/speech_preferences.dart';
import 'package:ai_for_app/ui/settings_page.dart';
import 'package:ai_for_app/main.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/extracted_record.dart';

import 'records_test.dart' show FakeScheduler;
import 'voice_input_test.dart' show LiveFakeRecorder;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const eventMethods = MethodChannel('local_journal/native_speech/events');
  final calls = <MethodCall>[];
  Future<void> emit(Map<String, dynamic> event) async {
    final done = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.channelBuffers.push(
      eventMethods.name,
      const StandardMethodCodec().encodeSuccessEnvelope(event),
      (_) => done.complete(),
    );
    await done.future;
  }

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(eventMethods, (_) async => null);
    messenger.setMockMethodCallHandler(NativeSpeech.channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(NativeSpeech.channel, null);
    messenger.setMockMethodCallHandler(eventMethods, null);
  });
  test('iOS defaults to native regardless of installed/auto-selected models; Android always uses local models', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(SpeechPreferences.useNative({}), true);
    expect(SpeechPreferences.liveEnabled({'liveSpeechEnabled': false}), true);
    expect(SpeechPreferences.useNative({'speechTranscriber': 'model'}), false);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(SpeechPreferences.useNative({}), false);
    expect(SpeechPreferences.useNative({'speechTranscriber': 'native'}), false);
    expect(SpeechPreferences.liveEnabled({}), false);
  });
  test(
    'native live PCM streams partial results and cancels idempotently',
    () async {
      final service = NativeSpeech();
      final texts = <String>[], errors = <Object>[];
      final session = await service.start(
        onText: texts.add,
        onError: errors.add,
      );
      final id = (calls.first.arguments as Map)['id'];
      session.addPcm(Uint8List.fromList([0, 0, 1, 0]));
      await Future<void>.delayed(Duration.zero);
      expect(calls.any((call) => call.method == 'append'), true);
      await emit({'id': id, 'type': 'text', 'text': '明天9点', 'final': false});
      expect(texts, ['明天9点']);
      await Future.wait([session.cancel(), session.cancel()]);
      expect(calls.where((call) => call.method == 'cancel').length, 1);
      expect(errors, isEmpty);
      await service.dispose();
    },
  );
  test('file transcription uses native file path, emits final text and releases request', () async {
    final service = NativeSpeech();
    final result = service.transcribe('/tmp/recording.wav').toList();
    while (!calls.any((c) => c.method == 'start')) {
      await Future<void>.delayed(Duration.zero);
    }
    final args = calls.firstWhere((c) => c.method == 'start').arguments as Map;
    expect(args['path'], '/tmp/recording.wav');
    await emit({
      'id': args['id'],
      'type': 'text',
      'text': '午饭20元',
      'final': true,
    });
    expect(await result, ['午饭20元']);
    expect(calls.last.method, 'cancel');
    await service.dispose();
  });
  test('speech permission failure propagates without leaving a hanging file stream', () async {
    messenger.setMockMethodCallHandler(NativeSpeech.channel, (call) async {
      calls.add(call);
      if (call.method == 'start') {
        throw PlatformException(code: 'permission', message: '未授权');
      }
      return null;
    });
    final service = NativeSpeech();
    await expectLater(
      service
          .transcribe('/tmp/recording.wav')
          .toList()
          .timeout(const Duration(seconds: 2)),
      throwsA(isA<PlatformException>()),
    );
    await service.dispose();
  });
  test(
    'iOS engine chooses native without requiring a downloaded speech model',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final store = LocalStore(Directory.systemTemp);
      final engine = AiEngine();
      final result = engine.transcribeStream(store, '/tmp/voice.wav').toList();
      while (!calls.any((c) => c.method == 'start')) {
        await Future<void>.delayed(Duration.zero);
      }
      final id =
          (calls.firstWhere((c) => c.method == 'start').arguments as Map)['id'];
      await emit({'id': id, 'type': 'text', 'text': '记录午饭20元', 'final': true});
      expect(await result, ['记录午饭20元']);
      await engine.dispose();
    },
  );
  test('bubble transcription always requires a local model on iOS without calling native', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final engine = AiEngine();
    final store = LocalStore(Directory.systemTemp);
    await expectLater(
      engine.transcribeModelStream(store, '/tmp/voice.wav').toList(),
      throwsStateError,
    );
    expect(calls, isEmpty);
    await engine.dispose();
  });
  test(
    'explicit model selection on iOS and Android never starts native speech',
    () async {
      final engine = AiEngine();
      final store = LocalStore(Directory.systemTemp);
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        debugDefaultTargetPlatformOverride = platform;
        store.data['speechTranscriber'] = 'model';
        await expectLater(
          engine.transcribeStream(store, '/tmp/voice.wav').toList(),
          throwsStateError,
        );
      }
      expect(calls, isEmpty);
      await engine.dispose();
    },
  );
  testWidgets(
    'iOS native live voice can trigger a record without any speech model download',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('native_voice_record'),
      ))!;
      final store = (await tester.runAsync(() => LocalStore.openAt(root)))!;
      store.models['chat'] = {
        'name': '文字',
        'capabilities': ['chat'],
      };
      final engine = AiEngine();
      final service = RecordService(
        RecordRepository(store.database),
        FakeScheduler(),
        (text, now) async => [
          const ExtractedRecord(
            kind: RecordKind.expense,
            title: '午饭',
            quote: '午饭花了20元',
            amountMinor: 2000,
            currency: 'CNY',
            direction: 'expense',
          ),
        ],
      );
      Future<void> flush() async {
        for (var i = 0; i < 12; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pumpAndSettle();
      }

      try {
        await tester.pumpWidget(
          MyApp(
            store: store,
            aiEngine: engine,
            voiceRecorder: LiveFakeRecorder(),
            recordService: service,
          ),
        );
        await flush();
        final point = tester.getCenter(find.byType(TextField));
        final touch = await tester.startGesture(point);
        await tester.pump(const Duration(milliseconds: 300));
        await flush();
        final id =
            (calls.firstWhere((call) => call.method == 'start').arguments
                as Map)['id'];
        await emit({
          'id': id,
          'type': 'text',
          'text': '帮我记一下午饭花了20元',
          'final': false,
        });
        await tester.pump();
        expect(find.text('帮我记一下午饭花了20元'), findsWidgets);
        await touch.moveTo(tester.getCenter(find.text('发语音')));
        await touch.up();
        await flush();
        expect((await tester.runAsync(service.repository.all))!.length, 1);
        expect(
          store.messages
              .where((m) => m['role'] == 'user')
              .single['voiceMessage'],
          true,
        );
        expect(store.model(ModelRole.speech), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await engine.dispose();
        await tester.runAsync(() async {
          await store.database.close();
          await root.delete(recursive: true);
        });
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
  testWidgets(
    'iOS settings can choose a local model and restore system default',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final root = await tester.runAsync(
        () => Directory.systemTemp.createTemp('native_preferences'),
      );
      final store = (await tester.runAsync(() => LocalStore.openAt(root!)))!;
      store.models['speech'] = {
        'name': 'Qwen3-ASR',
        'capabilities': ['speech'],
      };
      store.selected['speech'] = 'speech';
      Future<void> flush() async {
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pumpAndSettle();
      }

      try {
        await tester.pumpWidget(MaterialApp(home: SettingsPage(store: store)));
        expect(find.text('系统原生实时转写（默认）'), findsOneWidget);
        expect(find.text('边说边识别'), findsNothing);
        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<String> &&
                w.key.toString().contains('speech-transcriber-'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Qwen3-ASR').last);
        await flush();
        expect(store.data['speechTranscriber'], 'model');
        expect(store.selected['speech'], 'speech');
        expect(find.text('边说边识别'), findsOneWidget);
        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is DropdownButtonFormField<String> &&
                w.key.toString().contains('speech-transcriber-'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('系统原生实时转写（默认）').last);
        await flush();
        expect(SpeechPreferences.useNative(store.data), true);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await store.database.close();
          final reopened = await LocalStore.openAt(root!);
          expect(reopened.data['speechTranscriber'], 'native');
          await reopened.database.close();
        });
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => root!.delete(recursive: true));
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
