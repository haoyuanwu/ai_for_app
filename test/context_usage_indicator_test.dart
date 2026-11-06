import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_for_app/core/local_store.dart';
import 'package:ai_for_app/ui/context_usage_indicator.dart';

void main() {
  testWidgets('context meter updates on typing and exposes estimated usage', (
    tester,
  ) async {
    final store = LocalStore(Directory.systemTemp);
    final input = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContextUsageIndicator(
            store: store,
            input: input,
            hasImage: false,
          ),
        ),
      ),
    );
    final before = tester
        .widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        )
        .value!;
    expect(before, 0);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('预留 57%'), findsOneWidget);
    input.text = '新的消息内容';
    await tester.pump();
    final after = tester
        .widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        )
        .value!;
    expect(after, greaterThan(before));
    expect(find.text('预留 57%'), findsOneWidget);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      contains('估算'),
    );
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      contains('8192'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    input.dispose();
  });
}
