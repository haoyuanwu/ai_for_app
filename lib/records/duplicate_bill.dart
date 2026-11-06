/// Compare receipt facts, never the date when the chat message was sent.
class DuplicateBill {
  static DateTime? time(Map item) {
    for (final field in item['fields'] as List? ?? []) {
      if (!RegExp(r'交易时间|支付时间|付款时间|收款时间').hasMatch('${field['label']}')) {
        continue;
      }
      final parsed = _parse('${field['value']}');
      if (parsed != null) return parsed;
    }
    return _parse('${item['at'] ?? item['date'] ?? ''}');
  }

  static DateTime? _parse(String raw) {
    final normalized = raw
        .trim()
        .replaceAll(RegExp(r'\s*年\s*|\s*月\s*|/'), '-')
        .replaceAll(RegExp(r'\s*日\s*'), ' ')
        .trim();
    final day = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(normalized);
    if (day != null) {
      final year = int.parse(day[1]!),
          month = int.parse(day[2]!),
          date = int.parse(day[3]!);
      final valid = DateTime(year, month, date);
      if (valid.year != year || valid.month != month || valid.day != date) {
        return null;
      }
    }
    final iso = DateTime.tryParse(normalized);
    if (iso != null) return iso.toLocal();
    final match = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
    ).firstMatch(normalized);
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 6; i++) int.parse(match[i] ?? '0')];
    final result = DateTime(
      parts[0],
      parts[1],
      parts[2],
      parts[3],
      parts[4],
      parts[5],
    );
    if (result.year != parts[0] ||
        result.month != parts[1] ||
        result.day != parts[2] ||
        result.hour != parts[3] ||
        result.minute != parts[4] ||
        result.second != parts[5]) {
      return null;
    }
    return result;
  }

  static int _precision(Map item) {
    final text =
        '${item['at'] ?? ''} ${(item['fields'] as List? ?? []).where((f) => RegExp(r'交易时间|支付时间|付款时间|收款时间').hasMatch('${f['label']}')).map((f) => f['value']).join(' ')}';
    return RegExp(r'\d{1,2}:\d{2}:\d{2}').hasMatch(text)
        ? 2
        : RegExp(r'\d{1,2}:\d{2}').hasMatch(text)
        ? 1
        : 0;
  }

  static bool matches(Map candidate, Map saved) {
    if (candidate['kind'] != 'expense' ||
        saved['kind'] != 'expense' ||
        candidate['amountMinor'] == null ||
        candidate['amountMinor'] != saved['amountMinor'] ||
        candidate['currency'] == null ||
        candidate['currency'] != saved['currency'] ||
        (candidate['direction'] != null &&
            saved['direction'] != null &&
            candidate['direction'] != saved['direction'])) {
      return false;
    }
    final a = time(candidate), b = time(saved);
    if (a == null ||
        b == null ||
        a.year != b.year ||
        a.month != b.month ||
        a.day != b.day) {
      return false;
    }
    final precision = _precision(candidate) < _precision(saved)
        ? _precision(candidate)
        : _precision(saved);
    return precision == 0 ||
        (a.hour == b.hour &&
            a.minute == b.minute &&
            (precision == 1 || a.second == b.second));
  }
}
