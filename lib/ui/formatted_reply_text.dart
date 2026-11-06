import 'package:flutter/material.dart';

/// Small, inert formatting subset for local-model image answers. Keeping one
/// text widget preserves selection and lets unfinished streamed markup render.
class FormattedReplyText extends StatelessWidget {
  const FormattedReplyText({
    super.key,
    required this.text,
    required this.selectable,
  });
  final String text;
  final bool selectable;

  static List<InlineSpan> _inline(String text) {
    final spans = <InlineSpan>[];
    var offset = 0;
    for (final match in RegExp(r'\*\*([^*\n]+)\*\*').allMatches(text)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: text.substring(offset, match.start)));
      }
      spans.add(
        TextSpan(
          text: match[1],
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
      offset = match.end;
    }
    if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final spans = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      final heading = RegExp(r'^#{1,6}\s+(.+)$').firstMatch(lines[i]);
      final line =
          heading?[1] ?? lines[i].replaceFirst(RegExp(r'^\s*[-*]\s+'), '• ');
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      spans.add(
        TextSpan(
          children: _inline(line),
          style: heading == null
              ? null
              : const TextStyle(fontWeight: FontWeight.w700, height: 1.8),
        ),
      );
    }
    final content = TextSpan(children: spans);
    const style = TextStyle(fontSize: 16, height: 1.65);
    return selectable
        ? SelectableText.rich(content, style: style)
        : Text.rich(content, style: style);
  }
}
