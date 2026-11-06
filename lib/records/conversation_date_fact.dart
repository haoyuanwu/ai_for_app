import 'extracted_record.dart';

/// Resolve a clearly stated relative anniversary date. This is a draft fact,
/// never consent to save or to schedule a recurring reminder.
class ConversationDateFact {
  static List<ExtractedRecord> extract(String text, DateTime reference) {
    if (RegExp(r'如果|假如|假设|比如|例如|他说|她说|可能|也许|不确定|不是|不要|不用|取消|[？?]')
        .hasMatch(text)) {
      return [];
    }
    final records = <ExtractedRecord>[];
    for (final sentence in text.split(RegExp(r'[。！!\n]'))) {
      final quote = sentence.trim();
      final match = RegExp(
        r'^(?:请)?(?:(?:帮我|给我)?(?:记录|记住|记下|记一下)[，,:：\s]*)?(今天|昨天|明天|前天|后天)是(.{1,40}?(?:纪念日|周年日|周年纪念日))[，,\s]*(?:(?:请)?(?:帮我)?(?:记住|记录|记下|记一下))?$',
      ).firstMatch(quote);
      if (quote.isEmpty) continue;
      // Let the model handle mixed facts instead of dropping other sentences.
      if (match == null) return [];
      final offset = {'今天': 0, '昨天': -1, '明天': 1, '前天': -2, '后天': 2}[match[1]]!;
      // Calendar arithmetic avoids changing the date around DST transitions.
      final day = DateTime(
        reference.year,
        reference.month,
        reference.day + offset,
      );
      records.add(
        ExtractedRecord(
          kind: RecordKind.date,
          template: 'date',
          title: match[2]!.trim(),
          quote: quote,
          date:
              '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
        ),
      );
    }
    return records;
  }
}
