import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum VoiceReleaseAction { transcribe, sendAudio, cancel }

/// Observes touches without taking ordinary taps away from the text field.
class HoldToTalk extends StatefulWidget {
  const HoldToTalk({
    super.key,
    required this.enabled,
    required this.onStart,
    required this.onFinish,
    required this.child,
    required this.onActionChanged,
    this.onHoldChanged,
    this.resolveAction,
  });

  final bool enabled;
  final Future<bool> Function(bool Function() isHeld) onStart;
  final Future<void> Function(VoiceReleaseAction action) onFinish;
  final ValueChanged<VoiceReleaseAction> onActionChanged;
  final ValueChanged<bool>? onHoldChanged;
  final Widget child;
  final VoiceReleaseAction Function(Offset, VoiceReleaseAction)? resolveAction;

  @override
  State<HoldToTalk> createState() => _HoldToTalkState();
}

class _HoldToTalkState extends State<HoldToTalk> with WidgetsBindingObserver {
  Timer? _timer;
  int? _pointer;
  Offset _origin = Offset.zero;
  Future<bool>? _starting;
  VoiceReleaseAction _action = VoiceReleaseAction.transcribe;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _finish(cancel: true);
  }

  Future<void> _finish({bool cancel = false, bool notify = true}) async {
    _timer?.cancel();
    _pointer = null;
    if (notify) widget.onHoldChanged?.call(false);
    final starting = _starting;
    _starting = null;
    final action = cancel ? VoiceReleaseAction.cancel : _action;
    if (starting != null && await starting) {
      await widget.onFinish(action);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finish(cancel: true, notify: false);
    super.dispose();
  }

  void updateAction(Offset position) {
    final delta = position - _origin;
    final next =
        widget.resolveAction?.call(position, _action) ??
        (delta.dy < -60 || delta.dx < -56
            ? VoiceReleaseAction.cancel
            : delta.dx > 56
            ? VoiceReleaseAction.sendAudio
            : VoiceReleaseAction.transcribe);
    if (next != _action) {
      _action = next;
      widget.onActionChanged(next);
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (event) {
      if (!widget.enabled || _pointer != null || _starting != null) return;
      _pointer = event.pointer;
      _origin = event.position;
      _action = VoiceReleaseAction.transcribe;
      widget.onActionChanged(_action);
      _timer = Timer(const Duration(milliseconds: 200), () {
        widget.onHoldChanged?.call(true);
        _starting = widget.onStart(() => mounted && _pointer != null).then((
          started,
        ) {
          if (!started && mounted) widget.onHoldChanged?.call(false);
          return started;
        });
        HapticFeedback.lightImpact();
      });
    },
    onPointerMove: (event) {
      if (event.pointer != _pointer) return;
      if (_starting == null) {
        if ((event.position - _origin).distance > 18) _finish(cancel: true);
      } else {
        updateAction(event.position);
      }
    },
    onPointerUp: (event) {
      if (event.pointer == _pointer) {
        if (_starting != null) updateAction(event.position);
        _finish();
      }
    },
    onPointerCancel: (event) {
      if (event.pointer == _pointer) _finish(cancel: true);
    },
    child: widget.child,
  );
}
