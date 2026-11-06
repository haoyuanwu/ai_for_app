import 'dart:math' as math;

import 'package:flutter/material.dart';

class BubbleAction {
  const BubbleAction(this.value, this.label, this.icon, {this.enabled = true});
  final String value, label;
  final IconData icon;
  final bool enabled;
}

/// A horizontal action bar anchored near the pressed chat bubble.
class BubbleActionMenu extends StatelessWidget {
  const BubbleActionMenu({
    super.key,
    required this.actions,
    required this.onSelect,
  });
  final List<BubbleAction> actions;
  final ValueChanged<String> onSelect;

  static Future<String?> show(
    BuildContext context,
    Offset position,
    List<BubbleAction> actions,
  ) => showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭消息菜单',
    barrierColor: const Color(0x14000000),
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (menuContext, _, _) {
      final media = MediaQuery.of(menuContext);
      return CustomSingleChildLayout(
        delegate: _MenuPosition(
          position,
          media.padding,
          media.viewInsets.bottom,
          actions.length,
        ),
        child: BubbleActionMenu(
          actions: actions,
          onSelect: (value) => Navigator.pop(menuContext, value),
        ),
      );
    },
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    elevation: 4,
    shadowColor: const Color(0x24202e29),
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final action in actions)
                Expanded(
                  child: TextButton(
                    onPressed: action.enabled
                        ? () => onSelect(action.value)
                        : null,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 64),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(action.icon, size: 20),
                        const SizedBox(height: 6),
                        Text(
                          action.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MenuPosition extends SingleChildLayoutDelegate {
  _MenuPosition(this.anchor, this.padding, this.keyboard, this.count);
  final Offset anchor;
  final EdgeInsets padding;
  final double keyboard;
  final int count;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(
          0,
          math.min(
            count * 76.0 + 12,
            constraints.maxWidth - padding.horizontal - 24,
          ),
        ),
        maxHeight: math.max(
          0,
          constraints.maxHeight -
              padding.top -
              math.max(padding.bottom, keyboard) -
              24,
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = padding.left + 12;
    final top = padding.top + 12;
    final right = math.max(
      left,
      size.width - padding.right - childSize.width - 12,
    );
    final bottom = math.max(
      top,
      size.height - math.max(padding.bottom, keyboard) - childSize.height - 12,
    );
    final above = anchor.dy - childSize.height - 16;
    return Offset(
      (anchor.dx - childSize.width / 2).clamp(left, right),
      (above >= top ? above : anchor.dy + 16).clamp(top, bottom),
    );
  }

  @override
  bool shouldRelayout(covariant _MenuPosition old) =>
      old.anchor != anchor ||
      old.padding != padding ||
      old.keyboard != keyboard ||
      old.count != count;
}
