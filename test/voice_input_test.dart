import 'package:ai_for_app/ui/pressable_bubble.dart';

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_for_app/core/live_speech_session.dart';

import 'package:ai_for_app/core/ai_engine.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/core/voice_recorder.dart';
import 'package:ai_for_app/main.dart';
import 'package:ai_for_app/ui/record_media_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ai_for_app/records/record_repository.dart';
import 'package:ai_for_app/records/record_service.dart';
import 'package:ai_for_app/records/extracted_record.dart';

import 'records_test.dart' show FakeScheduler;

class FakeRecorder implements VoiceRecorder {
  Completer<bool>? permission;
  int starts = 0, stops = 0;
  String? path;
  @override
  Future<bool> hasPermission() async =>
      permission == null ? true : permission!.future;
  @override
  Future<void> start(String value) async {
    starts++;
    path = value;
    await File(value).writeAsBytes([1, 2, 3]);
  }

  @override
  Future<String?> stop() async {
    stops++;
    return path;
  }

  @override
  Future<void> dispose() async {}
}

class SpeechEngine extends AiEngine {
  int calls = 0;
  bool fail = false;
  String transcript = '明天早上提醒我开会';
  int replies = 0;
  @override
  Stream<String> reply(
    LocalStore store,
    String text, {
    String? image,
    void Function(String)? onRelationSaved,
    RecordService? recordService,
    void Function(String)? onMutationError,
  }) async* {
    replies++;
    yield '我听到了';
  }

  @override
  Future<String> transcribe(LocalStore store, String audio) =>
      transcribeModel(store, audio);
  @override
  Future<String> transcribeModel(LocalStore store, String audio) async {
    calls++;
    if (fail) throw StateError('转写失败');
    return transcript;
  }
}

class StreamingSpeechEngine extends SpeechEngine {
  final transcripts = StreamController<String>();
  @override
  Stream<String> transcribeStream(LocalStore store, String audio) =>
      transcripts.stream;
}

class LiveFakeRecorder extends FakeRecorder implements LiveVoiceRecorder {
  void Function(Uint8List)? onPcm;
  void Function(Object)? onFailure;
  @override
  Future<void> startLive(
    String path, {
    required void Function(Uint8List) onPcm,
    required void Function(Object) onError,
  }) async {
    this.onPcm = onPcm;
    onFailure = onError;
    await start(path);
  }
}

class LiveSpeechEngine extends SpeechEngine {
  bool unsupported = false;
  int decodeCalls = 0;
  String liveResult = '<asr_text>明天九点开会</asr_text>';
  @override
  Future<LiveSpeechSession> startLiveSpeech(
    LocalStore store, {
    required void Function(String) onText,
    required void Function(Object) onError,
  }) async {
    if (unsupported) throw UnsupportedError('模型不支持实时识别');
    return LiveSpeechSession(
      interval: Duration.zero,
      minimumBytes: 2,
      onText: onText,
      onError: onError,
      decode: (_) async* {
        decodeCalls++;
        yield liveResult;
      },
    );
  }
}

class DelayedLiveSpeechEngine extends LiveSpeechEngine {
  final ready = Completer<void>();
  @override
  Future<LiveSpeechSession> startLiveSpeech(
    LocalStore store, {
    required void Function(String) onText,
    required void Function(Object) onError,
  }) async {
    await ready.future;
    return super.startLiveSpeech(store, onText: onText, onError: onError);
  }
}

void main() {
  late Directory root;
  late LocalStore store;
  late FakeRecorder recorder;
  late SpeechEngine engine;
  RecordService? service;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('voice_input');
    store = await LocalStore.openAt(root);
    store.models['speech'] = {
      'name': 'SenseVoice',
      'capabilities': ['speech'],
    };
    store.selected['speech'] = 'speech';
    service = null;
    recorder = FakeRecorder();
    engine = SpeechEngine();
  });
  tearDown(() async {
    await store.database.close();
    await root.delete(recursive: true);
  });
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 24; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 20));
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
    await tester.pumpWidget(
      MyApp(
        store: store,
        voiceRecorder: recorder,
        aiEngine: engine,
        recordService: service,
      ),
    );
    await flush(tester);
  }

  testWidgets(
    'selection follows visible buttons with edge tolerance and returns to text',
    (tester) async {
      await show(tester);
      final origin = tester.getCenter(find.byType(TextField));
      final touch = await tester.startGesture(origin);
      await tester.pump(const Duration(milliseconds: 240));
      await flush(tester);
      final send = tester.getRect(find.text('发语音'));
      await touch.moveTo(send.center);
      await tester.pump();
      expect(find.text('松开发语音'), findsOneWidget);
      final sendBox = tester.getRect(
        find
            .ancestor(
              of: find.text('发语音'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      await touch.moveTo(Offset(sendBox.right + 15, sendBox.center.dy));
      await tester.pump();
      expect(find.text('松开发语音'), findsOneWidget);
      await touch.moveTo(tester.getCenter(find.text('取消')));
      await tester.pump();
      expect(find.text('松开取消'), findsOneWidget);
      await touch.moveTo(origin + const Offset(90, 0));
      await tester.pump();
      expect(find.text('松开转文字 · 滑到按钮选择'), findsOneWidget);
      await touch.moveTo(origin - const Offset(0, 40));
      await tester.pump();
      expect(find.text('松开转文字 · 滑到按钮选择'), findsOneWidget);
      await touch.moveTo(origin);
      await touch.up();
      await flush(tester);
      expect(find.text(engine.transcript), findsOneWidget);
      expect(store.messages, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'voice bubble contains only player controls and seconds, without organize text',
    (tester) async {
      store.messages.add({
        'role': 'user',
        'text': '这段文字不应出现在语音气泡里',
        'audio': '/voice.wav',
        'voiceMessage': true,
        'speechStatus': 'done',
        'status': 'done',
      });
      await show(tester);
      final bubble = find
          .ancestor(
            of: find.byTooltip('播放录音'),
            matching: find.byType(PressableBubble),
          )
          .first;
      final words = tester
          .widgetList<Text>(
            find.descendant(of: bubble, matching: find.byType(Text)),
          )
          .map((text) => text.data)
          .toList();
      expect(words, hasLength(1));
      expect(words.single, matches(r'^(?:[0-9]+|—)s$'));
      expect(find.text('自动整理'), findsNothing);
      expect(find.text('这段文字不应出现在语音气泡里'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'empty live transcription falls back to file and appends to the draft',
    (tester) async {
      final liveRecorder = LiveFakeRecorder();
      recorder = liveRecorder;
      engine = LiveSpeechEngine()..liveResult = '<asr_text></asr_text>';
      store.data['liveSpeechEnabled'] = true;
      await show(tester);
      await tester.enterText(find.byType(TextField), '草稿');
      final touch = await tester.startGesture(
        tester.getCenter(find.byType(TextField)),
      );
      await tester.pump(const Duration(milliseconds: 220));
      await flush(tester);
      liveRecorder.onPcm!(Uint8List(3200));
      await flush(tester);
      await touch.up();
      await flush(tester);
      expect(engine.calls, 1);
      expect(find.text('草稿${engine.transcript}'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'bubble conversion uses model instead of a cached input transcript',
    (tester) async {
      engine.transcript = '模型重新转写的内容';
      store.messages.add({
        'role': 'user',
        'text': '系统录入识别内容',
        'audio': '/missing.wav',
        'voiceMessage': true,
        'speechStatus': 'done',
        'status': 'done',
      });
      await show(tester);
      await tester.longPress(find.byType(RecordMediaView).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('转文字'));
      await flush(tester);
      expect(engine.calls, 1);
      expect(find.text('模型重新转写的内容'), findsOneWidget);
      expect(store.messages.single['modelTranscript'], engine.transcript);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'bubble menu edits text and expands cached voice text below audio',
    (tester) async {
      store.messages.addAll([
        {'role': 'user', 'text': '测试原文', 'status': 'done'},
        {
          'role': 'user',
          'text': '语音转写内容',
          'modelTranscript': '语音转写内容',
          'audio': '/missing.wav',
          'voiceMessage': true,
          'speechStatus': 'done',
          'status': 'done',
        },
      ]);
      await show(tester);
      await tester.longPress(find.text('测试原文'));
      await tester.pumpAndSettle();
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('再次发送'), findsOneWidget);
      expect(find.text('转文字'), findsNothing);
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '测试原文',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(RecordMediaView).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('转文字'));
      await tester.pumpAndSettle();
      expect(find.text('语音转写内容'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('语音转写内容')).dy,
        greaterThan(
          tester.getBottomLeft(find.byType(RecordMediaView).first).dy,
        ),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '测试原文',
      );
      expect(engine.calls, 0);
      expect(store.messages, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('resend creates a new voice turn and retains the draft', (
    tester,
  ) async {
    store.models['chat'] = {
      'name': '文字模型',
      'capabilities': ['chat'],
    };
    store.selected['chat'] = 'chat';
    store.messages.add({
      'role': 'user',
      'text': '你好',
      'audio': '/original.wav',
      'voiceMessage': true,
      'speechStatus': 'done',
      'status': 'done',
    });
    await show(tester);
    await tester.enterText(find.byType(TextField), '保留草稿');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(RecordMediaView).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('再次发送'));
    await flush(tester);
    expect(store.messages.where((m) => m['role'] == 'user'), hasLength(2));
    expect(engine.replies, 1);
    expect(engine.calls, 0);
    expect(find.text('保留草稿'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'microphone starts before a cold model and buffered audio appears once ready',
    (tester) async {
      final liveRecorder = LiveFakeRecorder();
      final delayed = DelayedLiveSpeechEngine();
      recorder = liveRecorder;
      engine = delayed;
      store.data['liveSpeechEnabled'] = true;
      await show(tester);
      final touch = await tester.startGesture(
        tester.getCenter(find.byType(TextField)),
      );
      await tester.pump(const Duration(milliseconds: 220));
      await flush(tester);
      expect(recorder.starts, 1);
      expect(delayed.ready.isCompleted, isFalse);
      expect(
        find.byKey(const ValueKey('voice-recording-overlay')),
        findsOneWidget,
      );
      liveRecorder.onPcm!(Uint8List(3200));
      delayed.ready.complete();
      await flush(tester);
      expect(find.text('明天9点开会'), findsOneWidget);
      await touch.up();
      await flush(tester);
      expect(find.text('明天9点开会'), findsOneWidget);
      expect(engine.calls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'release before model readiness transcribes the file and ignores late readiness',
    (tester) async {
      final liveRecorder = LiveFakeRecorder();
      final delayed = DelayedLiveSpeechEngine();
      recorder = liveRecorder;
      engine = delayed;
      store.data['liveSpeechEnabled'] = true;
      await show(tester);
      final touch = await tester.startGesture(
        tester.getCenter(find.byType(TextField)),
      );
      await tester.pump(const Duration(milliseconds: 220));
      await flush(tester);
      liveRecorder.onPcm!(Uint8List(3200));
      await touch.up();
      await flush(tester);
      expect(engine.calls, 1);
      expect(find.text(engine.transcript), findsOneWidget);
      delayed.ready.complete();
      await flush(tester);
      expect(find.text(engine.transcript), findsOneWidget);
      expect(
        find.byKey(const ValueKey('voice-recording-overlay')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'live speech displays while holding and appends the final text once',
    (tester) async {
      final liveRecorder = LiveFakeRecorder();
      recorder = liveRecorder;
      engine = LiveSpeechEngine();
      store.data['liveSpeechEnabled'] = true;
      await show(tester);
      await tester.enterText(find.byType(TextField), '草稿');
      final draftController = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;
      final touch = await tester.startGesture(
        tester.getCenter(find.byType(TextField)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await flush(tester);
      expect(find.text('正在听…'), findsOneWidget);
      liveRecorder.onPcm!(Uint8List(3200));
      await flush(tester);
      expect(find.text('明天9点开会'), findsOneWidget);
      expect(draftController.text, '草稿明天9点开会');
      expect((engine as LiveSpeechEngine).decodeCalls, 1);
      expect(recorder.stops, 0);
      expect(store.messages, isEmpty);
      await touch.up();
      await flush(tester);
      expect(find.text('草稿明天9点开会'), findsOneWidget);
      expect(engine.calls, 0);
      expect((engine as LiveSpeechEngine).decodeCalls, 1);
      expect(find.byKey(const ValueKey('live-speech-preview')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'live audio send reuses the transcript and preserves the typed draft',
    (tester) async {
      final liveRecorder = LiveFakeRecorder();
      recorder = liveRecorder;
      engine = LiveSpeechEngine();
      store.data['liveSpeechEnabled'] = true;
      store.models['chat'] = {
        'name': '文字模型',
        'capabilities': ['chat'],
      };
      store.selected['chat'] = 'chat';
      await show(tester);
      await tester.enterText(find.byType(TextField), '保留草稿');
      final point = tester.getCenter(find.byType(TextField));
      final touch = await tester.startGesture(point);
      await tester.pump(const Duration(milliseconds: 400));
      await flush(tester);
      liveRecorder.onPcm!(Uint8List(3200));
      await flush(tester);
      await touch.moveTo(tester.getCenter(find.text('发语音')));
      await touch.up();
      await flush(tester);
      final users = store.messages.where((m) => m['role'] == 'user');
      expect(users, hasLength(1));
      expect(users.single['text'], '明天9点开会');
      expect(users.single['voiceMessage'], isTrue);
      expect(engine.calls, 0);
      expect(engine.replies, 1);
      expect(find.text('保留草稿'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'live failure silently falls back and appends file transcription',
    (tester) async {
      final liveRecorder = LiveFakeRecorder();
      recorder = liveRecorder;
      engine = LiveSpeechEngine();
      store.data['liveSpeechEnabled'] = true;
      await show(tester);
      await tester.enterText(find.byType(TextField), '保留草稿');
      final touch = await tester.startGesture(
        tester.getCenter(find.byType(TextField)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await flush(tester);
      liveRecorder.onFailure!(StateError('麦克风中断'));
      await tester.pump();
      expect(find.textContaining('麦克风中断'), findsNothing);
      await touch.up();
      await flush(tester);
      expect(find.text('保留草稿${engine.transcript}'), findsOneWidget);
      expect(store.messages, isEmpty);
      expect(engine.calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'cancelling live speech discards the preview and preserves the draft',
    (tester) async {
      final liveRecorder = LiveFakeRecorder();
      recorder = liveRecorder;
      engine = LiveSpeechEngine();
      store.data['liveSpeechEnabled'] = true;
      await show(tester);
      await tester.enterText(find.byType(TextField), '草稿');
      final point = tester.getCenter(find.byType(TextField));
      final touch = await tester.startGesture(point);
      await tester.pump(const Duration(milliseconds: 400));
      await flush(tester);
      liveRecorder.onPcm!(Uint8List(3200));
      await flush(tester);
      await touch.moveTo(tester.getCenter(find.text('取消')));
      await touch.up();
      await flush(tester);
      expect(find.text('草稿'), findsOneWidget);
      expect(find.text('明天9点开会'), findsNothing);
      expect(
        await tester.runAsync(() => File(recorder.path!).exists()),
        isFalse,
      );
      expect(store.messages, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'unsupported live model silently records and falls back on release',
    (tester) async {
      recorder = LiveFakeRecorder();
      engine = LiveSpeechEngine()..unsupported = true;
      store.data['liveSpeechEnabled'] = true;
      await show(tester);
      final touch = await tester.startGesture(
        tester.getCenter(find.byType(TextField)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await flush(tester);
      await touch.up();
      await flush(tester);
      expect(find.textContaining('模型不支持实时识别'), findsNothing);
      expect(recorder.starts, 1);
      expect(engine.calls, 1);
      store.data['liveSpeechEnabled'] = false;
      final retry = await tester.startGesture(
        tester.getCenter(find.byType(TextField)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await flush(tester);
      await retry.up();
      await flush(tester);
      expect(recorder.starts, 2);
      expect(
        find.text('${engine.transcript}${engine.transcript}'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'hold window appears at 200ms before permission resolves and dismisses immediately on release',
    (tester) async {
      await show(tester);
      recorder.permission = Completer<bool>();
      final touch = await tester.startGesture(
        tester.getCenter(find.byType(TextField)),
      );
      await tester.pump(const Duration(milliseconds: 190));
      expect(
        find.byKey(const ValueKey('voice-recording-overlay')),
        findsNothing,
      );
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('正在准备麦克风…'), findsOneWidget);
      expect(find.text('正在聆听'), findsNothing);
      expect(recorder.starts, 0);
      await tester.pump(const Duration(milliseconds: 80));
      await touch.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('voice-recording-overlay')),
        findsNothing,
      );
      recorder.permission!.complete(true);
      await flush(tester);
      expect(recorder.starts, 0);
      expect(store.messages, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('composer is compact and taps still edit text', (tester) async {
    await show(tester);
    expect(
      tester.getSize(find.byKey(const ValueKey('chat-composer'))).height,
      lessThan(110),
    );
    expect(find.byTooltip('录音'), findsNothing);
    await tester.tap(find.byType(TextField));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.testTextInput.isVisible, isTrue);
    expect(recorder.starts, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('hold then release appends editable transcript without sending', (
    tester,
  ) async {
    await show(tester);
    await tester.enterText(find.byType(TextField), '原有草稿');
    final touch = await tester.startGesture(
      tester.getCenter(find.byType(TextField)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await flush(tester);
    expect(recorder.starts, 1);
    expect(find.text('松开转文字 · 滑到按钮选择'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-choice-transcribe')), findsNothing);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('发语音'), findsOneWidget);
    await touch.up();
    await flush(tester);
    expect(recorder.stops, 1);
    expect(engine.calls, 1);
    expect(find.text('原有草稿明天早上提醒我开会'), findsOneWidget);
    expect(store.messages, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'transcript snapshots appear before completion and preserve the draft',
    (tester) async {
      final streaming = StreamingSpeechEngine();
      engine = streaming;
      await show(tester);
      await tester.enterText(find.byType(TextField), '原有草稿');
      final touch = await tester.startGesture(
        tester.getCenter(find.byType(TextField)),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await flush(tester);
      await touch.up();
      await flush(tester);
      expect(
        find.byKey(const ValueKey('assistant-waiting-bubble')),
        findsOneWidget,
      );
      streaming.transcripts.add('明天9点');
      await tester.pump();
      expect(find.text('原有草稿明天9点'), findsOneWidget);
      expect(store.messages, isEmpty);
      streaming.transcripts.add('明天9点开会');
      await streaming.transcripts.close();
      await flush(tester);
      expect(find.text('原有草稿明天9点开会'), findsOneWidget);
      expect(find.text('已转成文字，可编辑后发送'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('assistant-waiting-bubble')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  Future<void> sendVoice(
    WidgetTester tester, {
    bool returnToCenter = false,
  }) async {
    // Wait for the previous voice turn to finish saving before starting again.
    for (
      var i = 0;
      i < 30 &&
          tester.widget<TextField>(find.byType(TextField)).enabled != true;
      i++
    ) {
      await flush(tester);
    }
    final point = tester.getCenter(find.byType(TextField));
    final touch = await tester.startGesture(point);
    await tester.pump(const Duration(milliseconds: 400));
    await flush(tester);
    await touch.moveTo(tester.getCenter(find.text('发语音')));
    await tester.pump();
    expect(find.text('松开发语音'), findsOneWidget);
    if (returnToCenter) {
      await touch.moveTo(point);
      await tester.pump();
    }
    await touch.up();
    await flush(tester);
  }

  void setupExpenseService() {
    store.models['chat'] = {
      'name': '文字模型',
      'capabilities': ['chat'],
    };
    service = RecordService(
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
  }

  testWidgets(
    'right swipe sends playable voice, creates requested record and retains typed draft',
    (tester) async {
      setupExpenseService();
      engine.transcript = '帮我记一下午饭花了20元';
      await show(tester);
      await tester.enterText(find.byType(TextField), '未发送的文字草稿');
      await sendVoice(tester);
      expect(find.byTooltip('播放录音'), findsOneWidget);
      expect(find.text('播放录音'), findsNothing);
      expect(find.text('查看文字'), findsNothing);
      expect(find.text('语音消息'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(
        tester.getSize(find.byType(LinearProgressIndicator).first).width,
        lessThanOrEqualTo(180),
      );
      expect(find.text('未发送的文字草稿'), findsOneWidget);
      final users = store.messages.where((m) => m['role'] == 'user').toList();
      expect(users.length, 1);
      expect(users.single['voiceMessage'], true);
      expect(users.single['speechStatus'], 'done');
      expect(users.single['text'], engine.transcript);
      expect(users.single['audio'], recorder.path);
      expect((await tester.runAsync(service!.repository.all))!.length, 1);
      expect(find.text('保存好了。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await store.database.close();
        store = await LocalStore.openAt(root);
        final saved = store.messages.firstWhere((m) => m['role'] == 'user');
        expect(saved['voiceMessage'], true);
        expect(await File(saved['audio'] as String).exists(), true);
      });
    },
  );
  testWidgets(
    'voice can query and confirm deletion without duplicate user turns',
    (tester) async {
      setupExpenseService();
      final repo = service!.repository;
      await tester.runAsync(() async {
        await repo.propose('initial', [
          const ExtractedRecord(
            kind: RecordKind.expense,
            title: '午饭',
            quote: '午饭20元',
            amountMinor: 2000,
            currency: 'CNY',
            direction: 'expense',
          ),
        ]);
        await repo.decide((await repo.proposals()).single.id, accept: true);
      });
      engine.transcript = '删除午饭记录';
      await show(tester);
      await sendVoice(tester);
      expect((await tester.runAsync(repo.all))!.length, 1);
      expect(store.data['pendingDeletion'], isNotNull);
      engine.transcript = '确认删除';
      await sendVoice(tester);
      expect((await tester.runAsync(repo.all))!, isEmpty);
      expect(store.messages.where((m) => m['voiceMessage'] == true).length, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'spoken questions reach AI as text while keeping a single voice bubble',
    (tester) async {
      store.models['chat'] = {
        'name': '文字模型',
        'capabilities': ['chat'],
      };
      service = RecordService(
        RecordRepository(store.database),
        FakeScheduler(),
        (text, now) async => [],
      );
      engine.transcript = '给我讲个笑话';
      await show(tester);
      await sendVoice(tester);
      expect(engine.replies, 1);
      expect(find.text('我听到了'), findsOneWidget);
      expect(store.messages.where((m) => m['role'] == 'user').length, 1);
      expect(store.messages.first['voiceMessage'], true);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'spoken reminder waits for missing time and a spoken answer completes it',
    (tester) async {
      store.models['chat'] = {
        'name': '文字模型',
        'capabilities': ['chat'],
      };
      final scheduler = FakeScheduler();
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final at = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9);
      service = RecordService(
        RecordRepository(store.database),
        scheduler,
        (text, now) async => [
          const ExtractedRecord(
            kind: RecordKind.reminder,
            title: '开会',
            quote: '明天开会',
          ),
        ],
        refiner: (proposal, text, now) async => [
          ExtractedRecord(
            kind: RecordKind.reminder,
            title: '开会',
            quote: '明天上午九点开会',
            at: at,
          ),
        ],
      );
      engine.transcript = '帮我记录提醒，明天开会';
      await show(tester);
      await sendVoice(tester);
      expect((await tester.runAsync(service!.repository.all))!, isEmpty);
      expect(scheduler.calls, 0);
      engine.transcript = '明天上午九点';
      await sendVoice(tester);
      expect((await tester.runAsync(service!.repository.all))!.length, 1);
      expect(scheduler.calls, 1);
      expect(scheduler.requests.values.single.isAtSameMomentAs(at), true);
      expect(store.messages.where((m) => m['voiceMessage'] == true).length, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'failed voice recognition keeps playable audio and cannot create records',
    (tester) async {
      setupExpenseService();
      engine.fail = true;
      await show(tester);
      await sendVoice(tester);
      expect(find.byTooltip('播放录音'), findsOneWidget);
      expect(find.text('播放录音'), findsNothing);
      expect(find.text('识别失败，未执行操作'), findsNothing);
      expect((await tester.runAsync(service!.repository.all))!, isEmpty);
      expect((await tester.runAsync(service!.repository.proposals))!, isEmpty);
      expect(engine.replies, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'returning from voice selection to center still transcribes without sending',
    (tester) async {
      await show(tester);
      await sendVoice(tester, returnToCenter: true);
      expect(find.text(engine.transcript), findsOneWidget);
      expect(store.messages, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'cancel selection waits for release and can return to transcribe',
    (tester) async {
      await show(tester);
      final point = tester.getCenter(find.byType(TextField));
      final touch = await tester.startGesture(point);
      await tester.pump(const Duration(milliseconds: 400));
      await flush(tester);
      await touch.moveTo(tester.getCenter(find.text('取消')));
      await tester.pump();
      expect(find.text('松开取消'), findsOneWidget);
      expect(recorder.stops, 0);
      await touch.moveTo(point);
      await touch.up();
      await flush(tester);
      expect(find.text(engine.transcript), findsOneWidget);
      expect(store.messages, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('sliding up cancels and deletes recording, retaining draft', (
    tester,
  ) async {
    await show(tester);
    await tester.enterText(find.byType(TextField), '保留草稿');
    final point = tester.getCenter(find.byType(TextField));
    final touch = await tester.startGesture(point);
    await tester.pump(const Duration(milliseconds: 400));
    await flush(tester);
    await touch.moveTo(tester.getCenter(find.text('取消')));
    await touch.up();
    await flush(tester);
    expect(recorder.stops, 1);
    expect(engine.calls, 0);
    expect(await tester.runAsync(() => File(recorder.path!).exists()), isFalse);
    expect(find.text('保留草稿'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('release during permission request never starts recording', (
    tester,
  ) async {
    await show(tester);
    recorder.permission = Completer<bool>();
    final touch = await tester.startGesture(
      tester.getCenter(find.byType(TextField)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await touch.up();
    recorder.permission!.complete(true);
    await flush(tester);
    expect(recorder.starts, 0);
    expect(engine.calls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('backgrounding cancels capture instead of transcribing', (
    tester,
  ) async {
    await show(tester);
    final touch = await tester.startGesture(
      tester.getCenter(find.byType(TextField)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await flush(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await flush(tester);
    await touch.up();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await flush(tester);
    expect(recorder.stops, 1);
    expect(engine.calls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('transcription failure shows error and retains editable draft', (
    tester,
  ) async {
    await show(tester);
    engine.fail = true;
    await tester.enterText(find.byType(TextField), '原有文字');
    final touch = await tester.startGesture(
      tester.getCenter(find.byType(TextField)),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await flush(tester);
    await touch.up();
    await flush(tester);
    expect(find.textContaining('录音或转写失败'), findsOneWidget);
    expect(find.text('原有文字'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
