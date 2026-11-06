import 'package:flutter/material.dart';

/// Local press feedback avoids rebuilding the conversation on each touch.
class PressableBubble extends StatefulWidget {
  const PressableBubble({
    super.key,
    required this.child,
    this.onTap,
    required this.onLongPressStart,
  });
  final Widget child;
  final VoidCallback? onTap;
  final GestureLongPressStartCallback onLongPressStart;
  @override
  State<PressableBubble> createState() => _PressableBubbleState();
}

class _PressableBubbleState extends State<PressableBubble> {
  bool pressed = false;
  void setPressed(bool value) {
    if (pressed != value) setState(() => pressed = value);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.onTap,
    onTapDown: widget.onTap == null ? null : (_) => setPressed(true),
    onTapUp: widget.onTap == null ? null : (_) => setPressed(false),
    onTapCancel: () => setPressed(false),
    onLongPressStart: (details) {
      setPressed(false);
      widget.onLongPressStart(details);
    },
    child: AnimatedScale(
      scale: pressed ? .985 : 1,
      alignment: Alignment.center,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}
