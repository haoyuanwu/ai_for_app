import 'package:flutter/material.dart';

import 'hold_to_talk.dart';

class VoiceRecordingChoices extends StatelessWidget {
  const VoiceRecordingChoices({
    super.key,
    required this.action,
    this.cancelKey,
    this.sendKey,
  });
  final VoiceReleaseAction action;
  final GlobalKey? cancelKey, sendKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        children: [
          Text(switch (action) {
            VoiceReleaseAction.transcribe => '松开转文字 · 滑到按钮选择',
            VoiceReleaseAction.sendAudio => '松开发语音',
            VoiceReleaseAction.cancel => '松开取消',
          }, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final (value, icon, label) in [
                (VoiceReleaseAction.cancel, Icons.close, '取消'),
                (VoiceReleaseAction.sendAudio, Icons.graphic_eq, '发语音'),
              ])
                Expanded(
                  child: Semantics(
                    selected: action == value,
                    child: AnimatedContainer(
                      duration: Duration(
                        milliseconds: MediaQuery.disableAnimationsOf(context)
                            ? 0
                            : 120,
                      ),
                      curve: Curves.easeOutCubic,
                      key: value == VoiceReleaseAction.cancel
                          ? cancelKey ?? const ValueKey('voice-choice-cancel')
                          : sendKey ?? const ValueKey('voice-choice-sendAudio'),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: action != value
                            ? colors.surfaceContainerLow
                            : value == VoiceReleaseAction.cancel
                            ? colors.errorContainer
                            : colors.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            icon,
                            size: 20,
                            color: action != value
                                ? colors.onSurfaceVariant
                                : value == VoiceReleaseAction.cancel
                                ? colors.onErrorContainer
                                : colors.onPrimary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              color: action != value
                                  ? colors.onSurfaceVariant
                                  : value == VoiceReleaseAction.cancel
                                  ? colors.onErrorContainer
                                  : colors.onPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
