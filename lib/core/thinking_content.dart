class ThinkingContent {
  const ThinkingContent(this.answer, this.thinking, this.inProgress);
  final String answer, thinking;
  final bool inProgress;
  static ThinkingContent parse(String raw) {
    final thoughts = <String>[];
    final answer = StringBuffer();
    var cursor = 0;
    var progress = false;
    final tag = RegExp(r'<(/?)think>', caseSensitive: false);
    var inside = false;
    var buffer = StringBuffer();
    for (final match in tag.allMatches(raw)) {
      final text = raw.substring(cursor, match.start);
      if (inside) {
        buffer.write(text);
      } else {
        answer.write(text);
      }
      if (match[1] == '/') {
        if (inside) {
          thoughts.add(buffer.toString());
          buffer = StringBuffer();
        } else if (thoughts.isEmpty) {
          thoughts.add(answer.toString());
          answer.clear();
        }
        inside = false;
      } else {
        inside = true;
      }
      cursor = match.end;
    }
    var tail = raw.substring(cursor);
    // A streamed delimiter must not flash as literal markup.
    for (final delimiter in ['<think>', '</think>']) {
      for (var n = delimiter.length - 1; n > 1; n--) {
        if (tail.toLowerCase().endsWith(delimiter.substring(0, n))) {
          tail = tail.substring(0, tail.length - n);
          break;
        }
      }
    }
    if (inside) {
      buffer.write(tail);
      thoughts.add(buffer.toString());
      progress = true;
    } else {
      answer.write(tail);
    }
    return ThinkingContent(
      answer.toString().trim(),
      thoughts.join('\n\n').trim(),
      progress,
    );
  }
}
