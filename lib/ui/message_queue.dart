import 'package:flutter/material.dart';

class QueuedMessage {
  QueuedMessage({required this.text, this.image, this.audio, this.replyTo});
  final String text;
  final String? image, audio, replyTo;
  String get label => text.isNotEmpty ? text : '图片消息';
}

class MessageQueueView extends StatelessWidget {
  const MessageQueueView({
    super.key,
    required this.messages,
    required this.expanded,
    required this.onToggle,
    required this.onGuide,
    required this.onDelete,
    required this.canGuide,
  });
  final List<QueuedMessage> messages;
  final bool expanded, canGuide;
  final VoidCallback onToggle;
  final ValueChanged<QueuedMessage> onGuide, onDelete;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const ValueKey('message-queue-toggle'),
                  onPressed: onToggle,
                  icon: Icon(expanded ? Icons.expand_more : Icons.expand_less),
                  label: Text('待发送 ${messages.length}'),
                ),
              ),
              if (expanded)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .22,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return Padding(
                        padding: const EdgeInsets.only(left: 12, right: 4),
                        child: Row(
                          children: [
                            Text(
                              '${index + 1}. ',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            Expanded(
                              child: Text(
                                message.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton(
                              onPressed: canGuide
                                  ? () => onGuide(message)
                                  : null,
                              child: const Text('引导'),
                            ),
                            IconButton(
                              tooltip: '删除排队消息',
                              onPressed: () => onDelete(message),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
