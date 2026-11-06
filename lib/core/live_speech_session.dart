import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'pcm_wave.dart';
import 'speech_transcript.dart';
import 'speech_capture_session.dart';

/// Coalesces PCM snapshots: one decode at a time, always using the newest audio.
/// The decoder stays loaded throughout the recording; audio remains on device.
class LiveSpeechSession implements SpeechCaptureSession {
  LiveSpeechSession({
    required this.decode,
    required this.onText,
    required this.onError,
    this.interval = const Duration(milliseconds: 1500),
    this.minimumBytes = 32000,
    this.onRelease,
    this.maxAudioBytes = 32000 * 60,
  });

  final Stream<String> Function(String wavePath) decode;
  final void Function(String) onText;
  final void Function(Object) onError;
  final Duration interval;
  final int minimumBytes;
  final int maxAudioBytes;
  final FutureOr<void> Function()? onRelease;
  Future<void>? _closing;
  final _pcm = BytesBuilder(copy: false);
  final _clock = Stopwatch()..start();
  int _lastRequest = 0, _decodedBytes = -1;
  Uint8List _audio = Uint8List(0);
  Future<void>? _work;
  Directory? _scratch;
  Object? _failure;
  String _text = '';
  bool _requested = false, _ended = false, _cancelled = false;

  @override
  void addPcm(Uint8List bytes) {
    if (_ended || _failure != null) return;
    if (_audio.length + _pcm.length + bytes.length > maxAudioBytes) {
      fail(StateError('实时预览已达到缓冲上限，松手后将完整转写'));
      _pcm.clear();
      return;
    }
    // Copy: platform buffers may be reused after their callback returns.
    _pcm.add(Uint8List.fromList(bytes));
    if (_audio.length + _pcm.length >= minimumBytes &&
        _clock.elapsedMilliseconds - _lastRequest >= interval.inMilliseconds) {
      _lastRequest = _clock.elapsedMilliseconds;
      _request();
    }
  }

  @override
  void fail(Object error) {
    if (_failure != null || _cancelled) return;
    _failure = error;
    onError(error);
  }

  void _request() {
    _requested = true;
    if (_work != null) return;
    _work = _drain().whenComplete(() => _work = null);
  }

  Future<void> _drain() async {
    try {
      while (_requested && !_cancelled && _failure == null) {
        _requested = false;
        if (_pcm.length > 0) {
          _audio =
              (BytesBuilder(copy: false)
                    ..add(_audio)
                    ..add(_pcm.takeBytes()))
                  .takeBytes();
        }
        // A model is never called with an empty waveform.
        if (_audio.isEmpty || _audio.length == _decodedBytes) continue;
        _scratch ??= await Directory.systemTemp.createTemp('live_asr_');
        final wave = File('${_scratch!.path}/snapshot.wav');
        final bytes = _audio.length - _audio.length % 2;
        final file = await wave.open(mode: FileMode.write);
        try {
          await file.writeFrom(pcmWaveHeader(bytes));
          await file.writeFrom(_audio, 0, bytes);
        } finally {
          await file.close();
        }
        var raw = '';
        await for (final token in decode(wave.path)) {
          if (_cancelled || _failure != null) break;
          raw += token;
          final partial = SpeechTranscript.clean(raw, partial: true);
          // A fresh snapshot decodes the same prefix again. Keep the current
          // preview until the decoder catches up and produces a new suffix.
          // Revisions of earlier words are applied once the snapshot completes.
          if (partial.length > _text.length && partial.startsWith(_text)) {
            _text = partial;
            onText(_text);
          }
        }
        if (!_cancelled && _failure == null) {
          final completed = SpeechTranscript.clean(raw);
          _decodedBytes = _audio.length;
          if (completed != _text) {
            _text = completed;
            onText(_text);
          }
        }
      }
    } catch (error) {
      fail(error);
    }
  }

  @override
  Future<String> finish() async {
    _ended = true;
    _request();
    try {
      await _work;
      if (_failure != null) throw _failure!;
      if (_text.trim().isEmpty) throw StateError('未识别到语音，请重新录制');
      return _text;
    } finally {
      await _cleanup();
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    _ended = true;
    _requested = false;
    await _work;
    await _cleanup();
  }

  Future<void> _cleanup() => _closing ??= _releaseResources();

  Future<void> _releaseResources() async {
    final scratch = _scratch;
    _scratch = null;
    _audio = Uint8List(0);
    _pcm.clear();
    try {
      if (scratch != null && await scratch.exists()) {
        await scratch.delete(recursive: true);
      }
    } finally {
      await onRelease?.call();
    }
  }
}
