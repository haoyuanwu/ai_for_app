import 'dart:async';

import 'package:ai_for_app/core/native_resource_pool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    '100 recordings reuse one model and drop it before changing model',
    () async {
      var alive = 0, peak = 0, loads = 0;
      final pool = NativeResourcePool<int>((_) => alive--);
      Future<int> load() async {
        alive++;
        if (alive > peak) peak = alive;
        return ++loads;
      }

      for (var i = 0; i < 100; i++) {
        final lease = await pool.acquire('speech', load);
        expect(lease.value, 1);
        lease.release(retain: true);
      }
      final chat = await pool.acquire('text', load);
      expect(chat.value, 2);
      expect(alive, 1);
      expect(peak, 1);
      chat.release();
      expect(alive, 0);
      await pool.close();
    },
  );
  test(
    'cancelled decoding holds its lease until native work finishes',
    () async {
      var loads = 0;
      final pool = NativeResourcePool<int>((_) {});
      final first = await pool.acquire('old', () async => ++loads);
      var acquired = false;
      final second = pool.acquire('new', () async => ++loads).then((lease) {
        acquired = true;
        return lease;
      });
      await Future<void>.delayed(Duration.zero);
      expect(acquired, false);
      expect(loads, 1);
      first.release();
      (await second).release();
      expect(loads, 2);
      await pool.close();
    },
  );
  test('loading failure does not poison subsequent recordings', () async {
    final pool = NativeResourcePool<int>((_) {});
    await expectLater(
      pool.acquire('bad', () async => throw StateError('load failed')),
      throwsStateError,
    );
    final next = await pool.acquire('good', () async => 3);
    expect(next.value, 3);
    next.release();
    await pool.close();
  });
  test(
    'memory pressure evicts a model safely after decode, including during load',
    () async {
      var destroys = 0;
      final pool = NativeResourcePool<int>((_) => destroys++);
      final loading = Completer<int>();
      final pending = pool.acquire('speech', () => loading.future);
      await Future<void>.delayed(Duration.zero);
      pool.evictIdle();
      loading.complete(1);
      final lease = await pending;
      expect(destroys, 0);
      lease.release(retain: true);
      expect(destroys, 1);
      final next = await pool.acquire('speech', () async => 2);
      next.release(retain: true);
      pool.evictIdle();
      expect(destroys, 2);
      await pool.close();
    },
  );
  test(
    'close waits for active inference and rejects queued/new loads',
    () async {
      var destroys = 0;
      final pool = NativeResourcePool<int>((_) => destroys++);
      final first = await pool.acquire('speech', () async => 1);
      final next = pool.acquire('text', () async => 2);
      final rejected = expectLater(next, throwsStateError);
      final closing = pool.close();
      first.release(retain: true);
      await rejected;
      await closing;
      expect(destroys, 1);
      await expectLater(pool.acquire('new', () async => 3), throwsStateError);
    },
  );
}
