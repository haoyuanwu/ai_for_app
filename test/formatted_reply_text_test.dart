import 'package:ai_for_app/ui/assistant_content.dart';
import 'package:ai_for_app/ui/formatted_reply_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'image answer renders headings, emphasis and readable list without markup',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: AssistantContent(
                    formatted: true,
                    text: '实付 **25.00 元**。\n\n### 交易信息\n- 商户：小卖部\n- 实付金额：**25.00 元**\n\n### 优惠信息\n- 红包抵扣：5.00 元',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final rich = tester.widget<SelectableText>(find.byType(SelectableText));
      final plain = rich.textSpan!.toPlainText();
      expect(plain, contains('• 实付金额：25.00 元'));
      expect(plain, contains('红包抵扣：5.00 元'));
      expect(plain, isNot(contains('**')));
      expect(plain, isNot(contains('###')));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unfinished streamed emphasis preserves text and completes in place',
    (tester) async {
      Future<void> show(String text) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FormattedReplyText(text: text, selectable: false),
          ),
        ),
      );
      await show('实付 **25.');
      expect(
        tester.widget<Text>(find.byType(Text)).textSpan!.toPlainText(),
        contains('25.'),
      );
      await show('实付 **25.00 元**');
      expect(
        tester.widget<Text>(find.byType(Text)).textSpan!.toPlainText(),
        '实付 25.00 元',
      );
    },
  );
}
