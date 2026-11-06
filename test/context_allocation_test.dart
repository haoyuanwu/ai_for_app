import 'package:ai_for_app/core/context_allocation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('llama context creation failure retries CPU once', () async {
    final attempts = <bool>[];
    final value = await ContextAllocation.load(
      useGpu: true,
      create: (gpu) async {
        attempts.add(gpu);
        if (gpu) {
          throw StateError(
            'Could not create context: null reference from llama.cpp',
          );
        }
        return 'ready';
      },
    );
    expect(value, 'ready');
    expect(attempts, [true, false]);
  });
  test('successful GPU allocation does not load another copy', () async {
    var count = 0;
    expect(
      await ContextAllocation.load(
        useGpu: true,
        create: (gpu) async {
          count++;
          return 1;
        },
      ),
      1,
    );
    expect(count, 1);
  });
  test(
    'missing and invalid model errors never trigger a second load',
    () async {
      var count = 0;
      await expectLater(
        ContextAllocation.load(
          useGpu: true,
          create: (gpu) async {
            count++;
            throw StateError('model file missing');
          },
        ),
        throwsStateError,
      );
      expect(count, 1);
    },
  );
  test('CPU allocation failure stays actionable and does not loop', () async {
    var count = 0;
    await expectLater(
      ContextAllocation.load(
        useGpu: true,
        create: (gpu) async {
          count++;
          throw StateError('Could not create context');
        },
      ),
      throwsA(predicate((e) => '$e'.contains('原消息已保留'))),
    );
    expect(count, 2);
  });
  test('a CPU-only model never retries allocation', () async {
    var count = 0;
    await expectLater(
      ContextAllocation.load(
        useGpu: false,
        create: (gpu) async {
          count++;
          throw StateError('Could not create context');
        },
      ),
      throwsStateError,
    );
    expect(count, 1);
  });
}
