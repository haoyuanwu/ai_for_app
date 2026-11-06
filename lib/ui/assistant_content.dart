import 'package:flutter/material.dart';

import '../core/thinking_content.dart';
import 'streaming_reply_text.dart';
import 'formatted_reply_text.dart';

class AssistantContent extends StatelessWidget {
  const AssistantContent({
    super.key,
    required this.text,
    this.streaming = false,
    this.formatted = false,
    this.selectable = true,
    this.animate = false,
    this.onAnimationStarted,
  });
  final String text;
  final bool streaming, formatted;
  final bool selectable;
  final bool animate;
  final VoidCallback? onAnimationStarted;
  @override
  Widget build(BuildContext context) {
    final content = ThinkingContent.parse(text);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (content.thinking.isNotEmpty || content.inProgress)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: ExpansionTile(
              key: const ValueKey('thinking-disclosure'),
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              shape: const Border(),
              collapsedShape: const Border(),
              leading: const Icon(Icons.auto_awesome_outlined, size: 18),
              title: Text(
                content.inProgress && streaming ? '正在思考…' : '思考过程',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                SelectableText(
                  content.thinking,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        StreamingReplyText(
          text: content.answer,
          animate: animate,
          onStarted: onAnimationStarted,
          builder: (visible) => visible.isEmpty
              ? const SizedBox.shrink()
              : formatted
              ? FormattedReplyText(text: visible, selectable: selectable)
              : selectable
              ? SelectableText(
                  visible,
                  style: const TextStyle(fontSize: 16, height: 1.65),
                )
              : Text(
                  visible,
                  style: const TextStyle(fontSize: 16, height: 1.65),
                ),
        ),
        if (content.answer.isEmpty &&
            content.thinking.isEmpty &&
            !content.inProgress &&
            streaming)
          const Text('正在加载模型…', style: TextStyle(height: 1.6)),
      ],
    );
  }
}
