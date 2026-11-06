import 'package:ai_for_app/records/image_payment_facts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_for_app/records/extracted_record.dart';

void main() {
  test('completed receipt OCR produces merchant, exact money and historical time', () {
    const text =
        '东阿阿胶健康连锁 -111.00 支付成功 支付时间 2020 年 3 月 2 日 11:36:10 商品 阿胶浆 商户全称 山东东阿阿胶健康管理连锁有限公司 收单机构 财付通支付科技有限公司';
    final record = ImagePaymentFacts.extract(text).single;
    expect(record.title, '东阿阿胶健康连锁');
    expect(record.amountMinor, 11100);
    expect(record.direction, 'expense');
    expect(record.date, '2020-03-02');
    expect(
      record.fields.singleWhere((field) => field['label'] == '交易时间')['value'],
      '2020 年 3 月 2 日 11:36:10',
    );
  });
  test('multiline detail keeps time below amount', () {
    final record = ImagePaymentFacts.extract(
      '微信支付\n早餐店\n-8.50\n支付成功\n支付时间 2026-11-05 09:30:00',
    ).single;
    expect(record.title, '早餐店');
    expect(record.date, '2026-11-05');
  });
  test('multiple completed payments exclude summary and failed rows', () {
    final records = ImagePaymentFacts.extract(
      '微信支付\n早餐店 -8.50元 支付成功\n书店 -20.00元 支付成功\n服装店 -30.00元 支付失败\n合计28.50元',
    );
    expect(records.map((r) => r.amountMinor), [850, 2000]);
  });
  test(
    'Alipay discounts are not independent payments and actual paid wins',
    () {
      const text = '支付宝\n商户 小卖部\n支付成功\n订单金额 ￥30.00\n红包抵扣 ￥5.00\n实付金额 ￥25.00';
      final records = ImagePaymentFacts.extract(text);
      expect(records.map((r) => r.amountMinor), [2500]);
      final wrong = ExtractedRecord(
        kind: RecordKind.expense,
        title: '小卖部',
        quote: text,
        amountMinor: 500,
        currency: 'CNY',
        direction: 'expense',
      );
      expect(
        ImagePaymentFacts.reconcile(text, [wrong]).single.amountMinor,
        2500,
      );
    },
  );
  test(
    'separate labels retain actual amount and reject standalone red packet',
    () {
      final records = ImagePaymentFacts.extract(
        '支付宝\n支付成功\n商户 小卖部\n红包\n￥5.00\n实付金额\n25.00',
      );
      expect(records.map((r) => r.amountMinor), [2500]);
      expect(ImagePaymentFacts.extract('支付宝\n支付成功\n红包\n￥5.00'), isEmpty);
      expect(ImagePaymentFacts.extract('支付宝\n支付成功\n已优惠 ￥5.00'), isEmpty);
    },
  );
  test('model cannot turn an identified discount into a payment without paid evidence', () {
    const text = '支付宝\n支付成功\n红包抵扣 ￥5.00\n实付金额 无法辨认';
    final wrong = ExtractedRecord(
      kind: RecordKind.expense,
      title: '账单',
      quote: text,
      amountMinor: 500,
      currency: 'CNY',
      direction: 'expense',
    );
    expect(ImagePaymentFacts.reconcile(text, [wrong]), isEmpty);
  });
  test('no completed payment or ambiguous money cannot fabricate expense', () {
    for (final text in [
      '预算111元',
      '支付失败 -111.00',
      '余额111元',
      '支付成功 订单金额120元 优惠9元 实付111元',
      '支付成功 USD 111元',
    ]) {
      expect(ImagePaymentFacts.extract(text), isEmpty);
    }
  });
}
