import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_for_app/core/live_speech_session.dart';
import 'package:ai_for_app/core/pcm_wave.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('concurrent cancellation releases native model once', () async {
    var released = 0;
    final session = LiveSpeechSession(
      onText: (_) {},
      onError: (_) {},
      decode: (_) => Stream.value('你好'),
      onRelease: () => released++,
    );
    await Future.wait([session.cancel(), session.cancel(), session.cancel()]);
    expect(released, 1);
  });
  test(
    'PCM accumulation is bounded and refuses more buffers after overflow',
    () async {
      final errors = <Object>[];
      var decoded = 0, released = 0;
      final session = LiveSpeechSession(
        maxAudioBytes: 100,
        minimumBytes: 200,
        onText: (_) {},
        onError: errors.add,
        decode: (_) {
          decoded++;
          return Stream.value('你好');
        },
        onRelease: () => released++,
      );
      session.addPcm(Uint8List(80));
      session.addPcm(Uint8List(80));
      for (var i = 0; i < 100; i++) {
        session.addPcm(Uint8List(1000));
      }
      expect(errors.length, 1);
      expect(decoded, 0);
      await session.cancel();
      expect(released, 1);
    },
  );
  test('replayed prefixes never rewind the preview and identical updates are skipped', () async {
    final initial = StreamController<String>();
    final started = Completer<void>();
    final outputs = <String>[];
    var calls = 0;
    final session = LiveSpeechSession(
      interval: Duration.zero,
      minimumBytes: 2,
      onText: outputs.add,
      onError: (error) => fail('$error'),
      decode: (_) async* {
        if (++calls == 1) {
          started.complete();
          yield* initial.stream;
        } else {
          for (final token in ['明', '天', '九', '点', '开', '会']) {
            yield token;
          }
        }
      },
    );
    session.addPcm(Uint8List(100));
    await started.future;
    initial.add('明天九点');
    // Queue another snapshot while the first decode is still in progress.
    session.addPcm(Uint8List(100));
    final result = session.finish();
    await initial.close();
    expect(await result, '明天9点开会');
    expect(outputs, ['明天9点', '明天9点开', '明天9点开会']);
  });

  test(
    'earlier-word corrections are applied once at snapshot completion',
    () async {
      final initial = StreamController<String>();
      final started = Completer<void>();
      final outputs = <String>[];
      var calls = 0;
      final session = LiveSpeechSession(
        interval: Duration.zero,
        minimumBytes: 2,
        onText: outputs.add,
        onError: (error) => fail('$error'),
        decode: (_) async* {
          if (++calls == 1) {
            started.complete();
            yield* initial.stream;
          } else {
            for (final token in ['明天', '去', '南京', '开会']) {
              yield token;
            }
          }
        },
      );
      session.addPcm(Uint8List(100));
      await started.future;
      initial.add('明天去北京');
      session.addPcm(Uint8List(100));
      final result = session.finish();
      await initial.close();
      expect(await result, '明天去南京开会');
      expect(outputs, ['明天去北京', '明天去南京开会']);
    },
  );

  test(
    'coalesces snapshots, flushes the final audio, and cleans scratch files',
    () async {
      final first = StreamController<String>();
      final started = Completer<void>();
      final sizes = <int>[];
      final outputs = <String>[];
      String? wavePath;
      var concurrent = 0, maximum = 0;
      final session = LiveSpeechSession(
        interval: Duration.zero,
        minimumBytes: 2,
        onText: outputs.add,
        onError: (error) => fail('$error'),
        decode: (path) async* {
          wavePath = path;
          concurrent++;
          if (concurrent > maximum) maximum = concurrent;
          final wave = await File(path).readAsBytes();
          sizes.add(ByteData.sublistView(wave).getUint32(40, Endian.little));
          try {
            if (sizes.length == 1) {
              started.complete();
              yield* first.stream;
            } else {
              yield '<asr_text>明天九点</asr_text>';
            }
          } finally {
            concurrent--;
          }
        },
      );
      session.addPcm(Uint8List(100));
      await started.future;
      session.addPcm(Uint8List(200));
      session.addPcm(Uint8List(300));
      final finish = session.finish();
      first.add('<asr_text>明天');
      await first.close();
      expect(await finish, '明天9点');
      expect(sizes, [100, 600]);
      expect(maximum, 1);
      expect(outputs.last, '明天9点');
      expect(await File(wavePath!).exists(), isFalse);
    },
  );

  test('cancellation ignores delayed output and deletes snapshots', () async {
    final tokens = StreamController<String>();
    final started = Completer<void>();
    final output = <String>[];
    String? wavePath;
    final session = LiveSpeechSession(
      interval: Duration.zero,
      minimumBytes: 2,
      onText: output.add,
      onError: (e) => fail('$e'),
      decode: (path) {
        wavePath = path;
        started.complete();
        return tokens.stream;
      },
    );
    session.addPcm(Uint8List(100));
    await started.future;
    final cancel = session.cancel();
    tokens.add('迟到的结果');
    await tokens.close();
    await cancel;
    expect(output, isEmpty);
    expect(await File(wavePath!).exists(), isFalse);
  });

  test('unsupported decoding reports an error once and does not silently fall back', () async {
    final errors = <Object>[];
    final session = LiveSpeechSession(
      onText: (_) {},
      onError: errors.add,
      decode: (path) => Stream.error(UnsupportedError('unsupported')),
    );
    session.addPcm(Uint8List(100));
    await expectLater(session.finish(), throwsUnsupportedError);
    expect(errors, hasLength(1));
  });

  test(
    'short audio is decoded on release and empty audio never reaches the model',
    () async {
      var calls = 0;
      LiveSpeechSession create() => LiveSpeechSession(
        onText: (_) {},
        onError: (_) {},
        decode: (_) async* {
          calls++;
          yield '你好';
        },
      );
      final short = create()..addPcm(Uint8List(20));
      expect(await short.finish(), '你好');
      expect(calls, 1);
      await expectLater(create().finish(), throwsStateError);
      expect(calls, 1);
      final header = ByteData.sublistView(pcmWaveHeader(32000));
      expect(header.getUint32(24, Endian.little), 16000);
      expect(header.getUint32(40, Endian.little), 32000);
    },
  );
}
