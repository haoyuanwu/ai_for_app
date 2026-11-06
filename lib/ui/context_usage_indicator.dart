import 'package:flutter/material.dart';

import '../core/conversation_context.dart';
import '../core/local_store.dart';

class ContextUsageIndicator extends StatelessWidget {
  const ContextUsageIndicator({
    super.key,
    required this.store,
    required this.input,
    required this.hasImage,
  });
  final LocalStore store;
  final TextEditingController input;
  final bool hasImage;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([input, ConversationContext.changes(store)]),
    builder: (context, _) {
      final used = ConversationContext.usage(
        store,
        input.text,
        image: hasImage,
      );
      final reserved = ConversationContext.reservedCost(store, image: hasImage);
      final content = used - reserved;
      final ratio = (content / ConversationContext.window).clamp(0.0, 1.0);
      final reservedPercent = (reserved / ConversationContext.window * 100)
          .round();
      final nearlyFull = used >= ConversationContext.window * .8;
      final percent = (ratio * 100).round();
      final compacting = ConversationContext.compacting(store);
      final saved = ConversationContext.summary(store).isNotEmpty;
      final label =
          '${compacting ? '正在压缩并保存摘要；' : ''}上下文估算，总容量 ${ConversationContext.window} tokens\n'
          '内容占用：$content tokens（含历史、摘要、草稿及图片估算）\n'
          '系统提示：${ConversationContext.systemCost(store, image: hasImage)} tokens\n'
          '工具预留：${ConversationContext.toolReserve} tokens\n'
          '回复预留：${ConversationContext.outputReserve} tokens\n'
          '合计预算：$used / ${ConversationContext.window} tokens${saved ? '；已保存历史摘要' : ''}';
      return Tooltip(
        message: label,
        child: Semantics(
          label: label,
          value: '内容 $percent%，预留 $reservedPercent%',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: ratio,
                          strokeWidth: 3,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          color: nearlyFull
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        ),
                        Text(
                          compacting ? '…' : '$percent%',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      compacting ? '正在压缩' : '内容占用',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      '预留 $reservedPercent%',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
