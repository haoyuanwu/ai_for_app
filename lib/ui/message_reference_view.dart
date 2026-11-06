import 'dart:io';

import 'package:flutter/material.dart';

import '../core/message_reference.dart';

class MessageReferenceView extends StatelessWidget {
  const MessageReferenceView({
    super.key,
    required this.source,
    this.onTap,
    this.onRemove,
    this.draft = false,
  });
  final Map<String, dynamic>? source;
  final VoidCallback? onTap, onRemove;
  final bool draft;
  @override
  Widget build(BuildContext context) {
    final image = source?['image'] as String?;
    final audio = source?['audio'] != null;
    final raw = source == null ? '引用的消息已不可用' : MessageReference.text(source!);
    final seconds = source?['audioDurationMs'] is num
        ? ((source!['audioDurationMs'] as num) / 1000).round()
        : null;
    final label = audio
        ? '音频消息${seconds == null ? '' : ' · $seconds 秒'}'
        : raw.trim().isEmpty
        ? (image != null
              ? '图片'
              : audio
              ? '音频消息'
              : '消息')
        : raw.replaceAll(RegExp(r'[\r\n]+'), ' ');
    final color = Theme.of(context).colorScheme;
    return Material(
      color: color.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300, minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color.primary, width: 3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (image != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: Image.file(
                    File(image),
                    width: draft ? 40 : 30,
                    height: draft ? 40 : 30,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined, size: 24),
                  ),
                ),
                const SizedBox(width: 8),
              ] else ...[
                Icon(
                  audio ? Icons.graphic_eq : Icons.format_quote_rounded,
                  size: 20,
                  color: color.primary,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: image == null && !audio
                    ? Text(
                        '${draft ? '引用 · ' : ''}${source?['role'] == 'user'
                            ? '我'
                            : source == null
                            ? '消息'
                            : 'AI'}：$label',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${draft ? '引用 · ' : ''}${source?['role'] == 'user'
                                ? '我'
                                : source == null
                                ? '消息'
                                : 'AI'}${audio
                                ? ' · 音频'
                                : image != null
                                ? ' · 图片'
                                : ''}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: '取消引用',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close, size: 18),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
