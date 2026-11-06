import 'extracted_record.dart';

/// Fallback for explicit completed payments in vision OCR, never chat replies.
class ImagePaymentFacts {
  static final _discount = RegExp(
    r'红包|优惠|折扣|抵扣|立减|减免|补贴|返现|积分|余额|合计|总计|原价|订单金额|商品金额',
  );
  static final _paid = RegExp(r'实付(?:金额)?|实际支付(?:金额)?|实际付款(?:金额)?|实际扣款(?:金额)?');
  static final _money = RegExp(
    r'(?<![\d.])[-−+¥￥]?\s*(\d+(?:\.\d{1,2})?)(?:\s*元)?(?![\d.])',
  );

  static Set<int> _labelledAmounts(String text, RegExp label) {
    final values = <int>{};
    final lines = text.split(RegExp(r'[\r\n]+'));
    for (var i = 0; i < lines.length; i++) {
      if (!label.hasMatch(lines[i])) continue;
      var tail = lines[i].substring(label.firstMatch(lines[i])!.end);
      if (tail.trim().replaceAll(RegExp(r'[：:¥￥\s]'), '').isEmpty &&
          i + 1 < lines.length) {
        tail = lines[i + 1];
      }
      final prefix = lines[i].substring(0, label.firstMatch(lines[i])!.start);
      final match = _money.firstMatch(tail) ?? _money.firstMatch(prefix);
      if (match != null) values.add((num.parse(match[1]!) * 100).round());
    }
    return values;
  }

  /// Reject model amounts that are explicitly labelled as discounts. For a
  /// single detail receipt, a clear actual-paid field takes precedence.
  static List<ExtractedRecord> reconcile(
    String text,
    List<ExtractedRecord> records,
  ) {
    final discounts = _labelledAmounts(text, _discount);
    final paid = _labelledAmounts(text, _paid);
    final expenses = records
        .where((r) => r.kind == RecordKind.expense)
        .toList();
    final singleReceipt = paid.length == 1 && expenses.length <= 1;
    final safe = records
        .where(
          (r) =>
              r.kind != RecordKind.expense ||
              r.amountMinor == null ||
              ((!discounts.contains(r.amountMinor) ||
                      paid.contains(r.amountMinor)) &&
                  (!singleReceipt || paid.contains(r.amountMinor))),
        )
        .toList();
    if (!safe.any((r) => r.kind == RecordKind.expense)) {
      safe.addAll(extract(text));
    }
    return safe;
  }

  static List<ExtractedRecord> extract(String text) {
    if (!RegExp(r'支付成功|交易成功|付款成功|转账成功|收款成功|已到账').hasMatch(text)) return [];
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();
    final amountPattern = RegExp(
      r'(?<![\d.])(?:[-−+]\s*\d+(?:\.\d{1,2})?|[¥￥]\s*\d+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?\s*元)(?![\d.])',
    );
    if (RegExp(r'USD|EUR|HKD|JPY|GBP|美元|欧元|港币|日元|英镑|\$').hasMatch(text)) {
      return [];
    }
    final monetaryLines = lines
        .where(
          (line) => amountPattern.hasMatch(line) && !_discount.hasMatch(line),
        )
        .length;
    final records = <ExtractedRecord>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (RegExp(r'未支付|待支付|交易关闭|交易失败|支付失败|已取消|退款中').hasMatch(line)) continue;
      if (_discount.hasMatch(line)) continue;
      if (index > 0 &&
          _discount.hasMatch(lines[index - 1]) &&
          RegExp(r'^[-−+¥￥\d.元\s]+$').hasMatch(line)) {
        continue;
      }
      final paidAmounts = _labelledAmounts(text, _paid);
      if (paidAmounts.isNotEmpty &&
          !_paid.hasMatch(line) &&
          !(index > 0 && _paid.hasMatch(lines[index - 1]))) {
        continue;
      }
      final paidLine =
          _paid.hasMatch(line) ||
          (index > 0 && _paid.hasMatch(lines[index - 1]));
      final matches = (paidLine ? _money : amountPattern)
          .allMatches(line)
          .toList();
      // Ambiguous totals/discounts are left to model extraction or clarification.
      if (matches.length != 1) continue;
      final match = matches.single;
      final literal = match.group(0)!;
      final value = num.tryParse(literal.replaceAll(RegExp(r'[^\d.]'), ''));
      if (value == null || value <= 0) continue;
      final quote = monetaryLines <= 1
          ? text
          : (records.isEmpty && index > 0
                ? '${lines.take(index).join('\n')}\n$line'
                : line);
      var merchant = line.substring(0, match.start).trim();
      merchant = merchant
          .replaceAll(RegExp(r'^(?:微信支付|支付宝|账单详情|交易详情)[：:\s]*'), '')
          .replaceAll(RegExp(r'(?:实付金额|付款金额|支付金额|金额|支出|收入)[：:\s]*$'), '')
          .trim();
      final namedMerchant = RegExp(
        r'(?:商户全称|收款方|商户)[：:\s]+([^\n]+?)(?=\s+(?:收单机构|支付方式|交易单号|支付时间)|$)',
      ).firstMatch(quote)?.group(1)?.trim();
      if (merchant.isEmpty || RegExp(r'^[-−+¥￥\s]*$').hasMatch(merchant)) {
        merchant =
            namedMerchant ?? (index > 0 ? lines[index - 1].trim() : '消费对象待补充');
      }
      final timeMatch = RegExp(
        r'(20\d{2})\s*(?:年|[-/])\s*(\d{1,2})\s*(?:月|[-/])\s*(\d{1,2})\s*日?\s*(?:(\d{1,2}):(\d{2})(?::(\d{2}))?)?',
      ).firstMatch(quote);
      String? date;
      final fields = <Map<String, String>>[];
      if (merchant != '消费对象待补充' && quote.contains(merchant)) {
        fields.add({'label': '商户', 'value': merchant});
      }
      if (timeMatch != null) {
        final year = int.parse(timeMatch[1]!);
        final month = int.parse(timeMatch[2]!);
        final day = int.parse(timeMatch[3]!);
        final parsed = DateTime(year, month, day);
        if (parsed.year == year && parsed.month == month && parsed.day == day) {
          date =
              '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
          fields.add({'label': '交易时间', 'value': timeMatch[0]!.trim()});
        }
      }
      records.add(
        ExtractedRecord(
          kind: RecordKind.expense,
          title: merchant,
          quote: quote,
          amountMinor: (value * 100).round(),
          currency: 'CNY',
          direction:
              literal.startsWith('+') || RegExp(r'收款成功|已到账|收入').hasMatch(line)
              ? 'income'
              : 'expense',
          date: date,
          fields: fields,
        ),
      );
    }
    return records;
  }
}
