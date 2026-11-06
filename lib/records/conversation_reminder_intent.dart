import 'extracted_record.dart';
import 'reminder_time.dart';

/// Exact single reminder requests do not depend on a small model emitting JSON.
class ConversationReminderIntent {
  static List<ExtractedRecord> extract(String text, DateTime reference) {
    if (RegExp(r'如果|假如|假设|比如|例如|他说|她说|不要|不用|取消|别提醒|怎么|如何|[？?\n]')
        .hasMatch(text)) {
      return [];
    }
    final match = RegExp(
      r'^(?:(?:请|麻烦你?)\s*)?(?:(?:帮我|给我)\s*)?(.*?)(?:提醒我|叫我|通知我)[，,:：\s]*(.{1,200}?)[。！!]*$',
    ).firstMatch(text.trim());
    if (match == null) return [];
    var time = match[1]!.trim();
    var task = match[2]!.trim();
    if (RegExp(r'[。；;！!]|提醒我|叫我|通知我|另外|然后').hasMatch(task)) return [];
    if (time.isNotEmpty &&
        !RegExp(
          r'^[0-9零〇一二两三四五六七八九十百年月日点时分秒钟后前大明今昨下本这周星期天上午中午下午晚早晨傍凌晨半整左右大概差不多每隔工作末 /:：-]+$',
        ).hasMatch(time)) {
      return [];
    }
    if (time.isEmpty) {
      final leading = RegExp(
        r'^(?:(?:今天|明天|后天|大后天|下周[一二三四五六日天]|星期[一二三四五六日天]|\d{1,2}月\d{1,2}日?)\s*)?(?:凌晨|早上|上午|中午|下午|晚上|傍晚)?\s*[零〇一二两三四五六七八九十\d]{1,3}(?:[:：][0-5]\d|[点时](?:[零〇一二两三四五六七八九十\d]{1,3}分?|半|整)?)',
      ).firstMatch(task);
      if (leading != null) {
        time = leading[0]!;
        task = task
            .substring(leading.end)
            .replaceFirst(RegExp(r'^[，,:：\s]+'), '')
            .trim();
      }
    }
    if (task.isEmpty || RegExp(r'是否|能不能|可不可以|吗$').hasMatch(task)) return [];
    var at = time.isEmpty || RegExp(r'之前|以前|最晚|至少|(?:点|分|时)前$').hasMatch(time)
        ? null
        : resolveReminderTime(time, reference);
    final past = at != null && !at.isAfter(reference);
    if (past) at = null;
    return [
      ExtractedRecord(
        kind: RecordKind.reminder,
        title: task,
        quote: text.trim(),
        at: at,
        body: past ? '这个时间已经过去，请补充要提醒的日期和时刻。' : null,
      ),
    ];
  }
}
