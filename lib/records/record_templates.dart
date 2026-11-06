const recordTemplates = <String, String>{
  'birthday': '生日卡片',
  'date': '日期卡片',
  'reminder': '提醒卡片',
  'expense': '记账卡片',
  'phone': '联系人卡片',
  'task': '事项卡片',
  'note': '文字卡片',
  'image': '图文卡片',
  'audio': '音频卡片',
};
String templateFor(Map<String, dynamic> data) {
  final value = data['template'];
  if (value is String && recordTemplates.containsKey(value)) return value;
  if ('${data['title']} ${data['category']} ${data['quote']}'.contains('生日')) {
    return 'birthday';
  }
  return recordTemplates.containsKey(data['kind'])
      ? data['kind'] as String
      : 'note';
}

int _chineseNumber(String value) {
  const digits = {
    '〇': 0,
    '零': 0,
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  if (value.contains('廿')) {
    return 20 + (value.length > 1 ? digits[value.substring(1)] ?? 0 : 0);
  }
  if (value.contains('十')) {
    final parts = value.split('十');
    return (parts.first.isEmpty ? 1 : digits[parts.first] ?? 0) * 10 +
        (parts.last.isEmpty ? 0 : digits[parts.last] ?? 0);
  }
  return int.parse(value.split('').map((v) => digits[v] ?? 0).join());
}

String _dateText(String quote) => quote.replaceAllMapped(
  RegExp(
    r'(?:([〇零一二三四五六七八九]{4})年)?([一二三四五六七八九十廿]{1,3})月([一二三四五六七八九十廿]{1,3})[日号]',
  ),
  (m) =>
      '${m[1] == null ? '' : '${_chineseNumber(m[1]!)}年'}${_chineseNumber(m[2]!)}月${_chineseNumber(m[3]!)}日',
);

Map<String, dynamic> presentRecord(Map<String, dynamic> raw) {
  final data = Map<String, dynamic>.from(raw);
  if (templateFor(data) == 'birthday' && data['date'] == null) {
    final quote = _dateText(data['quote'] as String? ?? '');
    if (RegExp(r'农历|阴历').hasMatch(quote)) {
      final lunar = RegExp(r'(?:\d{4}年)?\d{1,2}月\d{1,2}[日号]')
          .allMatches(quote)
          .toList();
      if (lunar.length == 1) data['birthdayText'] = '农历 ${lunar.single[0]}';
      data['template'] = 'birthday';
      return data;
    }
    final dates = RegExp(r'(\d{4})[年/.-](\d{1,2})[月/.-](\d{1,2})日?')
        .allMatches(quote)
        .toList();
    if (dates.length == 1) {
      final m = dates.single;
      final y = int.parse(m[1]!),
          month = int.parse(m[2]!),
          day = int.parse(m[3]!);
      final date = DateTime(y, month, day);
      if (date.year == y && date.month == month && date.day == day) {
        data['date'] =
            '${y.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      }
    } else if (dates.isEmpty) {
      final matches = RegExp(r'(\d{1,2})月(\d{1,2})[日号]')
          .allMatches(quote)
          .toList();
      if (matches.length == 1) {
        final m = int.parse(matches.single[1]!),
            d = int.parse(matches.single[2]!);
        final date = DateTime(2000, m, d);
        if (date.month == m && date.day == d) {
          data['birthdayMonthDay'] =
              '${m.toString().padLeft(2, '0')}月${d.toString().padLeft(2, '0')}日';
        }
      }
    }
  }
  data['template'] = templateFor(data);
  return data;
}

String displayDate(String? value) {
  if (value == null) return '日期待补充';
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  return match == null ? value : '${match[1]}年${match[2]}月${match[3]}日';
}
