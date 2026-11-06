import 'dart:io';

import 'package:ai_for_app/core/audio_duration.dart';
import 'package:ai_for_app/core/pcm_wave.dart';
import 'package:ai_for_app/ui/app_theme.dart';
import 'package:ai_for_app/ui/bubble_action_menu.dart';
import 'package:ai_for_app/ui/record_media_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'WAV duration is available without playing or decoding samples',
    () async {
      final dir = await Directory.systemTemp.createTemp('wave_duration');
      try {
        final file = await File('${dir.path}/minute.wav')
            .open(mode: FileMode.write);
        await file.writeFrom(pcmWaveHeader(60 * 32000));
        await file.setPosition(44 + 60 * 32000 - 1);
        await file.writeByte(0);
        await file.close();
        expect(
          await readWaveDuration('${dir.path}/minute.wav'),
          const Duration(seconds: 60),
        );
        expect(await readWaveDuration('${dir.path}/missing.wav'), isNull);
        await File('${dir.path}/invalid.wav').writeAsBytes([1, 2, 3]);
        expect(await readWaveDuration('${dir.path}/invalid.wav'), isNull);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'compact voice has seconds and a read-only progress bar before playback',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: journalTheme(),
          home: const Scaffold(
            body: Center(
              child: RecordMediaView(
                audio: '/not-opened.wav',
                compact: true,
                duration: Duration(seconds: 60),
              ),
            ),
          ),
        ),
      );
      expect(find.text('60s'), findsOneWidget);
      expect(find.text('语音消息'), findsNothing);
      expect(find.text('播放录音'), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(
        tester.getSize(find.byType(RecordMediaView)).width,
        lessThanOrEqualTo(180),
      );
      expect(
        tester.getSize(find.byType(RecordMediaView)).height,
        lessThanOrEqualTo(48),
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'custom bubble menu lays actions horizontally and stays on screen at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: journalTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await BubbleActionMenu.show(
                    context,
                    const Offset(318, 630),
                    const [
                      BubbleAction('copy', '复制', Icons.copy),
                      BubbleAction('resend', '再次发送', Icons.forward),
                      BubbleAction('edit', '编辑', Icons.edit),
                      BubbleAction('transcribe', '转文字', Icons.text_fields),
                    ],
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      final buttons = find.descendant(
        of: find.byType(BubbleActionMenu),
        matching: find.byType(TextButton),
      );
      expect(buttons, findsNWidgets(4));
      final rects = [for (var i = 0; i < 4; i++) tester.getRect(buttons.at(i))];
      for (var i = 1; i < 4; i++) {
        expect(rects[i].left, greaterThanOrEqualTo(rects[i - 1].right));
        expect(rects[i].top, rects.first.top);
      }
      final menu = tester.getRect(find.byType(BubbleActionMenu));
      expect(menu.left, greaterThanOrEqualTo(12));
      expect(menu.right, lessThanOrEqualTo(308));
      expect(menu.bottom, lessThanOrEqualTo(628));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('转文字'));
      await tester.pumpAndSettle();
      expect(result, 'transcribe');
      expect(find.byType(BubbleActionMenu), findsNothing);
    },
  );
}
