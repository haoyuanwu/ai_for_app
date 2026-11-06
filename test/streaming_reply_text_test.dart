import 'package:ai_for_app/ui/assistant_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'reply reveals intact characters and its bubble grows with the text',
    (tester) async {
      final text = ValueNotifier('你好👨‍👩‍👧‍👦，保存好了。');
      addTearDown(text.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ValueListenableBuilder<String>(
                valueListenable: text,
                builder: (_, value, _) => Container(
                  key: const ValueKey('bubble'),
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: AssistantContent(
                    text: value,
                    animate: true,
                    selectable: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 24));
      expect(find.text('你'), findsOneWidget);
      final early = tester.getSize(find.byKey(const ValueKey('bubble')));
      await tester.pump(const Duration(milliseconds: 48));
      expect(find.text('你好👨‍👩‍👧‍👦'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text(text.value), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('bubble'))).width,
        greaterThan(early.width),
      );
      text.value += '接下来的内容也会继续显示。';
      await tester.pump();
      expect(find.text('你好👨‍👩‍👧‍👦，保存好了。'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text(text.value), findsOneWidget);
    },
  );
  testWidgets(
    'real streamed chunks appear immediately without synthetic replay',
    (tester) async {
      final reply = ValueNotifier('');
      addTearDown(reply.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<String>(
            valueListenable: reply,
            builder: (_, text, _) => AssistantContent(
              text: text,
              streaming: true,
              animate: false,
              selectable: false,
            ),
          ),
        ),
      );
      reply.value = '你好';
      await tester.pump();
      expect(find.text('你好'), findsOneWidget);
      reply.value = '你好，我可以帮你记录。';
      await tester.pump();
      expect(find.text(reply.value), findsOneWidget);
    },
  );

  testWidgets('history and reduced motion display immediately', (tester) async {
    for (final reduced in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: AssistantContent(
              key: ValueKey(reduced),
              text: '保存好了。',
              animate: reduced,
            ),
          ),
        ),
      );
      expect(find.text('保存好了。'), findsOneWidget);
    }
  });
}
