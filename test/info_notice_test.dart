import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_for_app/ui/info_notice.dart';

void main() {
  testWidgets('normal notices expire and replace timer when text changes', (
    tester,
  ) async {
    var count = 0;
    Future<void> show(String text) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InfoNotice(message: text, onClose: () => count++),
          ),
        ),
      );
    }

    await show('整理完成');
    await tester.pump(const Duration(seconds: 3));
    expect(count, 0);
    await show('已保存');
    await tester.pump(const Duration(seconds: 3));
    expect(count, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(count, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('disposing notice cancels its timer', (tester) async {
    var count = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InfoNotice(message: '提示', onClose: () => count++),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    expect(count, 0);
  });
}
