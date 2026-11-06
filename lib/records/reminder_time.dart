/// Conservative local-time resolution for automatic notifications. Unsupported or
/// ambiguous phrases remain drafts rather than relying on a model-invented time.
DateTime? resolveReminderTime(String text, DateTime now) {
  if (RegExp(r'每天|每周|每月|每年|每隔|工作日|周末|早些|晚些|左右|大概|差不多').hasMatch(text)) {
    return null;
  }
  final relative = RegExp(r'([零〇一二两三四五六七八九十百\d]+)(分钟|小时|秒钟?)后')
      .firstMatch(text);
  if (relative != null) {
    final n = chineseNumber(relative[1]!);
    if (n == null || n <= 0 || n > 10000) return null;
    return now.add(
      Duration(
        seconds:
            n *
            (relative[2] == '分钟'
                ? 60
                : relative[2] == '小时'
                ? 3600
                : 1),
      ),
    );
  }
  final clock = RegExp(
    r'([零〇一二两三四五六七八九十\d]{1,3})(?:[:：]([0-5]\d)|[点时](?:([零〇一二两三四五六七八九十\d]{1,3})分?|半|整)?)',
  ).firstMatch(text);
  if (clock == null) return null;
  var hour = chineseNumber(clock[1]!);
  final minute = clock[2] != null
      ? int.tryParse(clock[2]!)
      : clock[3] != null
      ? chineseNumber(clock[3]!)
      : clock[0]!.contains('半')
      ? 30
      : 0;
  if (hour == null || minute == null || hour > 23 || minute > 59) return null;
  if (RegExp(r'下午|晚上|傍晚').hasMatch(text) && hour < 12) hour += 12;
  if (text.contains('中午') && hour < 11) hour += 12;
  if (RegExp(r'凌晨|早上|上午').hasMatch(text) && hour == 12) hour = 0;
  var day = DateTime(now.year, now.month, now.day);
  final absolute = RegExp(r'(?:(\d{4})[-年/])?(\d{1,2})[-月/](\d{1,2})日?')
      .firstMatch(text);
  if (absolute != null) {
    final year = int.tryParse(absolute[1] ?? '') ?? now.year;
    final month = int.parse(absolute[2]!);
    final d = int.parse(absolute[3]!);
    day = DateTime(year, month, d);
    if (day.month != month || day.day != d) return null;
  } else if (text.contains('大后天')) {
    day = DateTime(now.year, now.month, now.day + 3);
  } else if (text.contains('后天')) {
    day = DateTime(now.year, now.month, now.day + 2);
  } else if (text.contains('明天')) {
    day = DateTime(now.year, now.month, now.day + 1);
  } else if (RegExp(r'昨天|前天|去年|上周|上个月|下个月|明年').hasMatch(text)) {
    return null;
  } else {
    final week = RegExp(r'(下|本|这)?(?:周|星期)([一二三四五六日天])').firstMatch(text);
    if (week != null) {
      final weekday = '一二三四五六日'.indexOf(week[2]!.replaceAll('天', '日')) + 1;
      final delta = weekday - now.weekday + (week[1] == '下' ? 7 : 0);
      if (delta < 0) return null;
      day = DateTime(now.year, now.month, now.day + delta);
    }
  }
  return DateTime(day.year, day.month, day.day, hour, minute);
}

int? chineseNumber(String text) {
  final n = int.tryParse(text);
  if (n != null) return n;
  const digits = {
    '零': 0,
    '〇': 0,
    '一': 1,
    '二': 2,
    '两': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  if (digits.containsKey(text)) return digits[text];
  if (text.contains('十')) {
    final p = text.split('十');
    if (p.length != 2) return null;
    final tens = p[0].isEmpty ? 1 : digits[p[0]];
    final units = p[1].isEmpty ? 0 : digits[p[1]];
    if (tens != null && units != null) return tens * 10 + units;
  }
  return null;
}
