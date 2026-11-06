import 'package:ai_for_app/ui/voice_recording_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'overlay fades and moves in and out without blocking the held input',
    (tester) async {
      final visible = ValueNotifier(false);
      addTearDown(visible.dispose);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox.expand(),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: visible,
                  builder: (context, value, _) =>
                      VoiceRecordingOverlayTransition(
                        visible: value,
                        child: const ColoredBox(color: Colors.green),
                      ),
                ),
              ],
            ),
          ),
        ),
      );
      visible.value = true;
      await tester.pump();
      final open = find.byKey(const ValueKey('recording-window-open'));
      final fade = find
          .ancestor(
            of: open,
            matching: find.byKey(const ValueKey('voice-window-fade')),
          )
          .first;
      expect(tester.widget<FadeTransition>(fade).opacity.value, 0);
      await tester.pump(const Duration(milliseconds: 70));
      final midway = tester.widget<FadeTransition>(fade).opacity.value;
      expect(midway, greaterThan(0));
      expect(midway, lessThan(1));
      expect(
        find.ancestor(
          of: open,
          matching: find.byKey(const ValueKey('voice-window-slide')),
        ),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: open,
          matching: find.byKey(const ValueKey('voice-window-scale')),
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      await tester.tapAt(const Offset(200, 200));
      await tester.pump();
      expect(taps, 1);
      visible.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.widget<FadeTransition>(fade).opacity.value, lessThan(1));
      expect(open, findsOneWidget);
      await tester.pumpAndSettle();
      expect(open, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('reduced motion skips window transitions', (tester) async {
    final visible = ValueNotifier(false);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, value, _) => VoiceRecordingOverlayTransition(
              visible: value,
              child: const ColoredBox(color: Colors.green),
            ),
          ),
        ),
      ),
    );
    visible.value = true;
    await tester.pump();
    await tester.pump();
    final fade = find
        .ancestor(
          of: find.byKey(const ValueKey('recording-window-open')),
          matching: find.byKey(const ValueKey('voice-window-fade')),
        )
        .first;
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    visible.value = false;
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('recording-window-open')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
