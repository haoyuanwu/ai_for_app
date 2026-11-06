import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'pcm_wave.dart';

import 'package:record/record.dart';

/// Keeps platform recording separate from hold gestures and transcription.
abstract class VoiceRecorder {
  Future<bool> hasPermission();
  Future<void> start(String path);
  Future<String?> stop();
  Future<void> dispose();
}

abstract interface class LiveVoiceRecorder {
  Future<void> startLive(
    String path, {
    required void Function(Uint8List) onPcm,
    required void Function(Object) onError,
  });
}

abstract interface class VoiceRecorderPreparation {
  Future<void> prepare();
}

abstract interface class VoiceAmplitudeSource {
  Stream<double> get amplitudeLevels;
}

class LocalVoiceRecorder
    implements
        VoiceRecorder,
        LiveVoiceRecorder,
        VoiceAmplitudeSource,
        VoiceRecorderPreparation {
  @override
  Stream<double> get amplitudeLevels => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      .map((value) => ((value.current + 60) / 60).clamp(0.0, 1.0));

  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  RandomAccessFile? _wave;
  String? _livePath;
  int _byteLength = 0;
  bool _stopping = false;
  Future<void> _writes = Future<void>.value();

  @override
  Future<void> startLive(
    String path, {
    required void Function(Uint8List) onPcm,
    required void Function(Object) onError,
  }) async {
    final wave = await File(path).open(mode: FileMode.write);
    _wave = wave;
    _livePath = path;
    _byteLength = 0;
    _stopping = false;
    await wave.writeFrom(pcmWaveHeader(0));
    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _subscription = stream.listen(
        (bytes) {
          final copy = Uint8List.fromList(bytes);
          _writes = _writes.then((_) async {
            try {
              await wave.writeFrom(copy);
              _byteLength += copy.length;
            } catch (error) {
              onError(error);
            }
          });
          onPcm(bytes);
        },
        onError: (Object error) => onError(error),
        onDone: () {
          if (!_stopping) onError(StateError('录音流已中断，请重新录制'));
        },
      );
    } catch (_) {
      _wave = null;
      _livePath = null;
      await wave.close();
      if (await File(path).exists()) await File(path).delete();
      rethrow;
    }
  }

  @override
  Future<void> prepare() async {
    // Initialize the native recorder without opening a permission dialog.
    await _recorder.hasPermission(request: false);
  }

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String path) => _recorder.start(
    const RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
    ),
    path: path,
  );

  @override
  Future<String?> stop() async {
    _stopping = true;
    try {
      final path = await _recorder.stop();
      return _livePath ?? path;
    } finally {
      await _subscription?.cancel();
      _subscription = null;
      await _writes;
      final wave = _wave;
      _wave = null;
      _livePath = null;
      if (wave != null) {
        try {
          await wave.setPosition(0);
          await wave.writeFrom(pcmWaveHeader(_byteLength));
        } finally {
          await wave.close();
        }
      }
    }
  }

  @override
  Future<void> dispose() async {
    try {
      if (_wave != null) await stop();
    } finally {
      await _recorder.dispose();
    }
  }
}
