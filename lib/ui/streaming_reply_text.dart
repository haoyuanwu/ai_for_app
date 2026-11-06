import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Reveals grapheme clusters, preserving emoji and Chinese characters.
class StreamingReplyText extends StatefulWidget {
  const StreamingReplyText({
    super.key,
    required this.text,
    required this.animate,
    required this.builder,
    this.onStarted,
  });
  final String text;
  final bool animate;
  final Widget Function(String visible) builder;
  final VoidCallback? onStarted;
  @override
  State<StreamingReplyText> createState() => _StreamingReplyTextState();
}

class _StreamingReplyTextState extends State<StreamingReplyText> {
  Timer? _timer;
  late final bool _animate = widget.animate;
  List<String> _characters = [];
  int _visible = 0;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      widget.onStarted?.call();
      _update();
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _timer?.cancel();
      _visible = _characters.length;
    }
  }

  @override
  void didUpdateWidget(covariant StreamingReplyText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _update();
  }

  void _update() {
    final oldText = _characters.take(_visible).join();
    _characters = widget.text.characters.toList();
    if (!_animate || MediaQuery.disableAnimationsOf(context)) {
      _visible = _characters.length;
      _timer?.cancel();
      return;
    }
    // A corrected model prefix is applied atomically rather than replayed.
    if (oldText.isNotEmpty && !widget.text.startsWith(oldText)) {
      _visible = math.min(_visible, _characters.length);
    }
    _timer?.cancel();
    if (_visible >= _characters.length) return;
    _timer = Timer.periodic(const Duration(milliseconds: 24), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final step = math.max(1, ((_characters.length - _visible) / 40).ceil());
      setState(() => _visible = math.min(_characters.length, _visible + step));
      if (_visible >= _characters.length) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(_characters.take(_visible).join());
}
