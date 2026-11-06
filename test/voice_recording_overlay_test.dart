import 'dart:io';
import 'dart:ui' as ui;

import 'package:ai_for_app/ui/app_theme.dart';
import 'package:ai_for_app/ui/hold_to_talk.dart';
import 'package:ai_for_app/ui/voice_recording_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'recording preview is high and actions remain clear of the held finger',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final boundary = GlobalKey();
      for (final size in [const Size(390, 844), const Size(414, 896)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            theme: journalTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(1),
              ),
              child: RepaintBoundary(
                key: boundary,
                child: Scaffold(
                  appBar: AppBar(title: const Text('本地随记')),
                  body: Stack(
                    children: [
                      const Center(child: Text('聊天内容')),
                      Positioned.fill(
                        bottom: 140,
                        child: VoiceRecordingOverlay(
                          action: VoiceReleaseAction.transcribe,
                          text: '明天下午三点，提醒我带上资料去开会。',
                          live: true,
                          levels: List.generate(
                            28,
                            (i) => [0.1, 0.2, 0.5, 0.8, 0.4, 0.7, 0.3][i % 7],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('live-speech-preview')))
              .dy,
          lessThan(size.height / 2),
        );
        if (size.width < 500) {
          expect(
            tester.getBottomLeft(find.text('发语音')).dy,
            lessThan(size.height - 150),
          );
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('/tmp/voice-recording-overlay.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
