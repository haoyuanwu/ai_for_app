import 'package:flutter/material.dart';

import 'hold_to_talk.dart';
import 'voice_recording_choices.dart';

/// Visual-only overlay: the original hold gesture continues receiving moves.
class VoiceRecordingOverlay extends StatelessWidget {
  const VoiceRecordingOverlay({
    super.key,
    required this.action,
    required this.text,
    required this.levels,
    required this.live,
    this.ready = true,
    this.cancelKey,
    this.sendKey,
  });
  final VoiceReleaseAction action;
  final GlobalKey? cancelKey, sendKey;
  final String text;
  final List<double> levels;
  final bool live;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: ColoredBox(
        key: const ValueKey('voice-recording-overlay'),
        color: colors.surface.withValues(alpha: .97),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...[
                        Row(
                          children: [
                            Icon(Icons.mic, size: 18, color: colors.primary),
                            const SizedBox(width: 8),
                            Text(
                              ready ? '正在聆听' : '正在准备麦克风…',
                              style: TextStyle(
                                color: colors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],
                      Expanded(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: LayoutBuilder(
                            builder: (context, viewport) =>
                                SingleChildScrollView(
                                  reverse: true,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: viewport.maxHeight,
                                    ),
                                    child: Align(
                                      alignment: Alignment.topLeft,
                                      child: Text(
                                        text.isNotEmpty
                                            ? text
                                            : !ready
                                            ? '准备好后即可说话'
                                            : live
                                            ? '正在听…'
                                            : '说出你想记录的内容',
                                        key: const ValueKey(
                                          'live-speech-preview',
                                        ),
                                        style: TextStyle(
                                          fontSize: 26,
                                          height: 1.5,
                                          fontWeight: FontWeight.w500,
                                          color: text.isNotEmpty
                                              ? colors.onSurface
                                              : colors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                          ),
                        ),
                      ),
                      SizedBox(height: 24),
                      Center(
                        child: Semantics(
                          label: '麦克风音量',
                          value:
                              '${((levels.isEmpty ? 0 : levels.last) * 100).round()}%',
                          child: CustomPaint(
                            key: const ValueKey('voice-waveform'),
                            size: Size(220, 48),
                            painter: _WavePainter(
                              levels,
                              action == VoiceReleaseAction.cancel
                                  ? colors.error
                                  : colors.primary,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      VoiceRecordingChoices(
                        action: action,
                        cancelKey: cancelKey,
                        sendKey: sendKey,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Keep entry/exit feedback independent of microphone and model startup.
class VoiceRecordingOverlayTransition extends StatelessWidget {
  const VoiceRecordingOverlayTransition({
    super.key,
    required this.visible,
    required this.child,
  });
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: reducedMotion ? 0 : 160),
        reverseDuration: Duration(milliseconds: reducedMotion ? 0 : 100),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInQuad,
        transitionBuilder: (child, animation) => KeyedSubtree(
          key: ValueKey(child.key),
          child: FadeTransition(
            key: const ValueKey('voice-window-fade'),
            opacity: animation,
            child: SlideTransition(
              key: const ValueKey('voice-window-slide'),
              position: Tween(
                begin: const Offset(0, .035),
                end: Offset.zero,
              ).animate(animation),
              child: ScaleTransition(
                key: const ValueKey('voice-window-scale'),
                scale: Tween(begin: .98, end: 1.0).animate(animation),
                child: child,
              ),
            ),
          ),
        ),
        child: visible
            ? KeyedSubtree(
                key: const ValueKey('recording-window-open'),
                child: child,
              )
            : const SizedBox.shrink(key: ValueKey('recording-window-closed')),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.levels, this.color);
  final List<double> levels;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final step = size.width / levels.length;
    for (var i = 0; i < levels.length; i++) {
      final height = 4 + levels[i].clamp(0, 1) * (size.height - 4);
      final x = step * (i + .5);
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.levels != levels || oldDelegate.color != color;
}
