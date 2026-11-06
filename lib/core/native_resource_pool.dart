import 'dart:async';

/// One native model in memory at a time. A lease includes in-flight decoding.
class NativeResourcePool<T> {
  NativeResourcePool(this.destroy);
  final void Function(T) destroy;
  Future<void> _tail = Future.value();
  T? _resource;
  Object? _key;
  bool _closed = false, _leased = false, _evict = false;

  Future<NativeResourceLease<T>> acquire(
    Object key,
    Future<T> Function() create,
  ) async {
    if (_closed) throw StateError('推理引擎已关闭');
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      if (_closed) throw StateError('推理引擎已关闭');
      _leased = true;
      if (_resource == null || _key != key || _evict) {
        _clear();
        _resource = await create();
        _key = key;
      }
      return NativeResourceLease(_resource as T, (retain) {
        try {
          if (!retain || _closed || _evict) _clear();
        } finally {
          _leased = false;
          done.complete();
        }
      });
    } catch (_) {
      _leased = false;
      done.complete();
      rethrow;
    }
  }

  void _clear() {
    final resource = _resource;
    _resource = null;
    _key = null;
    _evict = false;
    if (resource != null) destroy(resource);
  }

  void evictIdle() {
    if (_leased) {
      _evict = true;
    } else {
      _clear();
    }
  }

  Future<void> close() async {
    _closed = true;
    await _tail;
    _clear();
  }
}

class NativeResourceLease<T> {
  NativeResourceLease(this.value, this._release);
  final T value;
  final void Function(bool retain) _release;
  bool _released = false;
  void release({bool retain = false}) {
    if (_released) return;
    _released = true;
    _release(retain);
  }
}
