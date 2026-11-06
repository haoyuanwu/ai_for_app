import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform execution grant shared by nested model operations and a chat turn.
class BackgroundExecution {
  static const channel = MethodChannel('ai_for_app/background_execution');
  static final status = ValueNotifier<String?>(null);
  static int _owners = 0;
  static Future<void>? _starting;
  static Completer<void>? _resume;
  static bool _initialized = false;
  static bool _available = true;
  static DateTime _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
  static bool get mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);
  static void initialize() {
    if (_initialized || !mobile) return;
    _initialized = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'expired') {
        _resume ??= Completer<void>();
        status.value = '系统后台执行时间已用尽，已保留进度，回到前台后继续…';
      } else if (call.method == 'resumed') {
        final pending = _resume;
        _resume = null;
        pending?.complete();
        status.value = null;
      }
    });
  }

  static Future<Future<void> Function()> acquire() async {
    if (!mobile) return () async {};
    initialize();
    _owners++;
    if (_owners == 1) {
      _starting = () async {
        if (!_available) return;
        try {
          await channel.invokeMethod<void>('begin');
        } on MissingPluginException {
          _available = false;
        } on PlatformException catch (e) {
          status.value = '后台执行申请未获准：${e.message}，请保持前台以完成当前任务';
        }
      }();
    }
    await _starting;
    var released = false;
    return () async {
      if (released) return;
      released = true;
      _owners--;
      if (_owners == 0) {
        _starting = null;
        try {
          if (_available) await channel.invokeMethod<void>('end');
        } on MissingPluginException {
          /* Unit tests. */
        } on PlatformException {
          /* Native task already ended. */
        }
        status.value = null;
      }
    };
  }

  static Future<T> run<T>(Future<T> Function() operation) async {
    final release = await acquire();
    try {
      await waitUntilAllowed();
      return await operation();
    } finally {
      await release();
    }
  }

  static Future<void> waitUntilAllowed() async {
    await _resume?.future;
  }

  static void progress() {
    if (!mobile ||
        _owners == 0 ||
        DateTime.now().difference(_lastProgress).inSeconds < 1) {
      return;
    }
    _lastProgress = DateTime.now();
    unawaited(channel.invokeMethod<void>('progress').catchError((Object _) {}));
  }
}
