import 'package:flutter/material.dart';

/// A persistent notice; dismissal is always explicit.
class ErrorNotice extends StatelessWidget {
  const ErrorNotice({super.key, required this.message, required this.onClose});
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: colors.errorContainer,
        shadowColor: Colors.black12,
        elevation: 3,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 12),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: colors.onErrorContainer,
              fontSize: 14,
              height: 1.5,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 20,
                      color: colors.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '操作未完成',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭错误通知',
                      onPressed: onClose,
                      icon: Icon(Icons.close, color: colors.onErrorContainer),
                    ),
                  ],
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 12),
                    child: SelectableText(message),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
