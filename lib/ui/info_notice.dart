import 'dart:async';

import 'package:flutter/material.dart';

class InfoNotice extends StatefulWidget {
  const InfoNotice({super.key, required this.message, required this.onClose});
  final String message;
  final VoidCallback onClose;
  @override
  State<InfoNotice> createState() => _InfoNoticeState();
}

class _InfoNoticeState extends State<InfoNotice> {
  Timer? timer;
  void restart() {
    timer?.cancel();
    timer = Timer(const Duration(seconds: 4), widget.onClose);
  }

  @override
  void initState() {
    super.initState();
    restart();
  }

  @override
  void didUpdateWidget(covariant InfoNotice old) {
    super.didUpdateWidget(old);
    if (old.message != widget.message) restart();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: colors.primaryContainer,
        elevation: 3,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: colors.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.message,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.onPrimaryContainer),
                ),
              ),
              IconButton(
                tooltip: '关闭提示',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
