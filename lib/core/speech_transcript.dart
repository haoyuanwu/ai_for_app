import 'dart:convert';

/// Presentation cleanup shared by streaming and complete ASR results.
class SpeechTranscript {
  static const _digits = {
    '零': '0',
    '〇': '0',
    '一': '1',
    '二': '2',
    '两': '2',
    '三': '3',
    '四': '4',
    '五': '5',
    '六': '6',
    '七': '7',
    '八': '8',
    '九': '9',
    '幺': '1',
  };
  static const _number = r'[零〇一二两三四五六七八九幺十百千万亿]+';

  static String clean(String raw, {bool partial = false}) {
    var text = raw.trim();
    if (text.startsWith('{')) {
      try {
        final value = jsonDecode(text);
        if (value is Map && value['asr_text'] is String) {
          text = value['asr_text'] as String;
        }
      } on FormatException {
        if (partial) return '';
      }
    }
    text = text.replaceFirst(
      RegExp(r'^language\s+[^<\n]+(?=<)', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<\|[^<>]*\|>|</?asr_text\s*>', caseSensitive: false),
      '',
    );
    if (partial) {
      final start = text.lastIndexOf('<');
      if (start >= 0 && !text.substring(start).contains('>')) {
        text = text.substring(0, start);
      }
    }
    text = text
        .replaceFirst(RegExp(r'^asr_text\s*[:：]\s*', caseSensitive: false), '')
        .trim();
    // Decimal quantities, before normalizing individual numbers with units.
    text = text.replaceAllMapped(
      RegExp('($_number)点([零〇一二三四五六七八九]+)(?=元|块|公斤|千克|米|升|度|%)'),
      (m) => '${_convert(m[1]!)}.${_convert(m[2]!)}',
    );
    text = text.replaceAllMapped(
      RegExp('$_number(?=年|月|日|号|元|块|角|分|秒|岁|个|次|公里|公斤|千克|米|升|度|点(?!心|儿|子))'),
      (m) => _convert(m[0]!),
    );
    // Digit-by-digit identifiers, e.g. telephone numbers; retain leading zeroes.
    text = text.replaceAllMapped(
      RegExp(r'[零〇一二三四五六七八九幺]{3,}'),
      (m) => _convert(m[0]!),
    );
    if (RegExp('^$_number\$').hasMatch(text)) text = _convert(text);
    return text;
  }

  static String _convert(String value) {
    if (!RegExp(r'[十百千万亿]').hasMatch(value)) {
      return value.split('').map((c) => _digits[c] ?? c).join();
    }
    const units = {'十': 10, '百': 100, '千': 1000, '万': 10000, '亿': 100000000};
    var total = 0, section = 0, digit = 0;
    for (final char in value.split('')) {
      if (_digits.containsKey(char)) {
        digit = int.parse(_digits[char]!);
      } else {
        final unit = units[char]!;
        if (unit < 10000) {
          section += (digit == 0 ? 1 : digit) * unit;
        } else {
          section += digit;
          total = unit == 100000000
              ? (total + section) * unit
              : total + section * unit;
          section = 0;
        }
        digit = 0;
      }
    }
    return '${total + section + digit}';
  }
}
