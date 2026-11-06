import 'dart:async';
import 'dart:collection';

import 'package:flutter/services.dart';
import 'package:synchronized/synchronized.dart';

import 'speech_capture_session.dart';

/// Apple Speech consumes the same PCM stream that `record` saves as a WAV.
/// Neither a second microphone owner nor a downloaded model is needed.
class NativeSpeech {
  static const channel = MethodChannel('local_journal/native_speech');
  static const events = EventChannel('local_journal/native_speech/events');
  final _lock = Lock();
  NativeSpeechSession? _current;
  Stream<dynamic>? _events;

  Future<NativeSpeechSession> start({
    String? file,
    required void Function(String) onText,
    required void Function(Object) onError,
  }) => _lock.synchronized(() async {
    await _current?.cancel();
    final session = NativeSpeechSession._(
      DateTime.now().microsecondsSinceEpoch,
      onText,
      onError,
    );
    _current = session;
    session._subscription = (_events ??= events.receiveBroadcastStream())
        .listen(session._event, onError: session.fail);
    try {
      await channel.invokeMethod<void>('start', {
        'id': session.id,
        'path': ?file,
      });
      return session;
    } catch (error) {
      await session.cancel();
      rethrow;
    }
  });

  Stream<String> transcribe(String file) async* {
    final snapshots = StreamController<String>();
    NativeSpeechSession? session;
    try {
      session = await start(file: file, onText: snapshots.add, onError: (_) {});
      unawaited(session._done.future.then((_) => snapshots.close()));
      yield* snapshots.stream;
      if (session._failure != null) throw session._failure!;
      if (session.text.isEmpty) throw StateError('未识别到语音，请重新录制');
    } finally {
      await session?.cancel();
      unawaited(snapshots.close());
    }
  }

  Future<void> dispose() async {
    await _current?.cancel();
    _current = null;
  }
}

class NativeSpeechSession implements SpeechCaptureSession {
  NativeSpeechSession._(this.id, this.onText, this.onError);
  final int id;
  final void Function(String) onText;
  final void Function(Object) onError;
  final _done = Completer<void>();
  StreamSubscription<dynamic>? _subscription;
  final _queue = Queue<Uint8List>();
  int _queuedBytes = 0;
  Future<void>? _sending, _closing;
  Object? _failure;
  bool _cancelled = false, _finishing = false;
  String text = '';

  void _event(dynamic event) {
    if (_cancelled || event is! Map || event['id'] != id) return;
    if (event['type'] == 'error') {
      fail(StateError(event['message'] as String? ?? '系统语音识别失败'));
      return;
    }
    if (event['type'] == 'text') {
      text = (event['text'] as String? ?? '').trim();
      onText(text);
      if (event['final'] == true && !_done.isCompleted) _done.complete();
    }
  }

  @override
  void addPcm(Uint8List bytes) {
    if (_cancelled || _finishing || _failure != null || bytes.isEmpty) return;
    if (_done.isCompleted) {
      fail(StateError('实时识别已结束，将在松手后完整转写'));
      return;
    }
    if (_queuedBytes + bytes.length > 64000) {
      fail(StateError('系统识别繁忙，将在松手后完整转写'));
      return;
    }
    _queue.add(Uint8List.fromList(bytes));
    _queuedBytes += bytes.length;
    _sending ??= _drain().whenComplete(() => _sending = null);
  }

  Future<void> _drain() async {
    try {
      while (_queue.isNotEmpty && !_cancelled && _failure == null) {
        final bytes = _queue.removeFirst();
        _queuedBytes -= bytes.length;
        await NativeSpeech.channel.invokeMethod<void>('append', {
          'id': id,
          'pcm': bytes,
        });
      }
    } catch (error) {
      if (!_done.isCompleted) fail(error);
    }
  }

  @override
  void fail(Object error) {
    if (_cancelled || _failure != null) return;
    _failure = error;
    _queue.clear();
    _queuedBytes = 0;
    onError(error);
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<String> finish() async {
    _finishing = true;
    try {
      await _sending;
      await NativeSpeech.channel.invokeMethod<void>('finish', {'id': id});
      await _done.future.timeout(const Duration(seconds: 8));
      if (_failure != null) throw _failure!;
      if (text.isEmpty) throw StateError('未识别到语音');
      return text;
    } finally {
      await cancel();
    }
  }

  @override
  Future<void> cancel() => _closing ??= _cancel();
  Future<void> _cancel() async {
    _cancelled = true;
    _queue.clear();
    _queuedBytes = 0;
    try {
      await NativeSpeech.channel.invokeMethod<void>('cancel', {'id': id});
    } finally {
      await _subscription?.cancel();
      _subscription = null;
      if (!_done.isCompleted) _done.complete();
    }
  }
}
