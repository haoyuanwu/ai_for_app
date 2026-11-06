import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_for_app/core/thinking_content.dart';
import 'package:ai_for_app/ui/assistant_content.dart';

void main() {
  test(
    'separates reasoning, multiple blocks, streaming tags and plain text',
    () {
      final parsed = ThinkingContent.parse('<think>分析过程</think>正式回复');
      expect(parsed.answer, '正式回复');
      expect(parsed.thinking, '分析过程');
      expect(parsed.inProgress, false);
      final partial = ThinkingContent.parse('<think>还在想');
      expect(partial.answer, isEmpty);
      expect(partial.inProgress, true);
      expect(ThinkingContent.parse('正文<thi').answer, '正文');
      expect(ThinkingContent.parse('3 <').answer, '3 <');
      expect(
        ThinkingContent.parse('<THINK>甲</THINK>一<think>乙</think>二').thinking,
        '甲\n\n乙',
      );
      expect(ThinkingContent.parse('隐式思考</think>答案').answer, '答案');
    },
  );
  testWidgets(
    'reasoning defaults collapsed, expands on request and stays closed during streaming',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AssistantContent(text: '<think>内部推理内容</think>正式回答'),
          ),
        ),
      );
      expect(find.text('正式回答'), findsOneWidget);
      expect(find.text('内部推理内容').hitTestable(), findsNothing);
      await tester.tap(find.text('思考过程'));
      await tester.pumpAndSettle();
      expect(find.text('内部推理内容').hitTestable(), findsOneWidget);
      await tester.tap(find.text('思考过程'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AssistantContent(text: '<think>新的思考', streaming: true),
          ),
        ),
      );
      expect(find.text('正在思考…'), findsOneWidget);
      expect(find.text('新的思考').hitTestable(), findsNothing);
    },
  );
}
