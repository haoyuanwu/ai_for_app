import 'package:ai_for_app/core/message_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 5, 15);
  test('legacy missing/null/invalid time is persisted and stable on retry', () {
    for (final message in <Map<String, dynamic>>[
      {'role': 'user', 'kind': 'deletion_decision'},
      {'time': null},
      {'time': 123},
      {'time': 'invalid'},
    ]) {
      expect(ensureMessageTime(message, now), now);
      expect(message['time'], now.toIso8601String());
      expect(ensureMessageTime(message, now.add(const Duration(days: 1))), now);
    }
  });
  test('existing timestamp remains the reference for relative dates', () {
    final message = <String, dynamic>{'time': '2026-11-04T23:30:00+08:00'};
    expect(
      ensureMessageTime(message, now),
      DateTime.parse(message['time']).toLocal(),
    );
    expect(message['time'], '2026-11-04T23:30:00+08:00');
  });
}
