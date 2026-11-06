import 'dart:convert';

import 'package:ai_for_app/core/inference_parameters.dart';
import 'package:ai_for_app/core/record_prompts.dart';
import 'package:ai_for_app/records/extracted_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nobodywho/nobodywho.dart' as nw;

void main() {
  test('Qwen3.5 text and vision use distinct non-thinking profiles', () {
    final text = InferenceParameters.chat({'name': 'Qwen3.5 0.8B · Q4_K_M'})!;
    expect(
      (text.temperature, text.topP, text.topK, text.presencePenalty),
      (1.0, 1.0, 20, 2.0),
    );
    final vision = InferenceParameters.chat({
      'catalogId': 'qwen35-4b-q4',
    }, vision: true)!;
    expect(
      (vision.temperature, vision.topP, vision.topK, vision.presencePenalty),
      (.7, .8, 20, 1.5),
    );
    expect(
      InferenceParameters.extraction.temperature,
      lessThan(text.temperature),
    );
    expect(InferenceParameters.extraction.presencePenalty, 0);
  });
  test('few-shot assistant records validate against their paired user facts and schema order', () {
    final now = DateTime(2026, 11, 4, 16);
    final messages = recordExtractionMessages('本轮新的事实', now);
    expect((messages.last as nw.Message_User).content.text, contains('本轮新的事实'));
    for (var i = 1; i < messages.length - 1; i += 2) {
      final user = (messages[i] as nw.Message_User).content.text;
      final raw = user.contains('仅分析以下用户原文：\n')
          ? user.split('仅分析以下用户原文：\n').last
          : user;
      final source = (jsonDecode(raw) as Map)['text'] as String;
      final answer = (messages[i + 1] as nw.Message_Assistant).content.text;
      expect(
        () => ExtractedRecord.parse(answer, source, reference: now),
        returnsNormally,
      );
    }
    final item =
        ((recordExtractionSchema['properties'] as Map)['records']
                as Map)['items']
            as Map;
    expect((item['properties'] as Map).keys.toList(), item['required']);
  });
  test('other model families keep runtime defaults', () {
    for (final name in [
      'Qwen3 VL 4B Instruct',
      'DeepSeek R1',
      'MiMo 7B',
      'MiniCPM5 2B',
    ]) {
      expect(InferenceParameters.chat({'name': name}), isNull);
    }
  });
  test(
    'draft amounts convert minor units exactly and never leak storage keys',
    () {
      final original = [
        for (final amount in [2000, 50, 2001])
          ExtractedRecord(
            kind: RecordKind.expense,
            title: '支出',
            quote: '花费',
            amountMinor: amount,
            currency: 'CNY',
            direction: 'expense',
          ).toJson(),
      ];
      final draft = extractionDraft(original);
      expect(draft.map((r) => r['amount']), ['20.00', '0.50', '20.01']);
      expect(original.first['amountMinor'], 2000);
      final required =
          ((recordExtractionSchema['properties'] as Map)['records']
                  as Map)['items']['required']
              as List;
      expect(draft.first.keys.toSet(), required.toSet());
      expect(draft.first.containsKey('amountMinor'), isFalse);
      expect(draft.first.containsKey('at'), isFalse);
    },
  );
  test(
    'timestamps contain seconds and exactly one valid UTC or local zone',
    () {
      final utc = DateTime.utc(2026, 11, 4, 9, 10, 11, 123);
      expect(recordTimestamp(utc), '2026-11-04T09:10:11Z');
      expect(
        DateTime.parse(recordTimestamp(utc)),
        DateTime.utc(2026, 11, 4, 9, 10, 11),
      );
      final local = DateTime(2026, 11, 4, 9, 10, 11);
      expect(
        DateTime.parse(recordTimestamp(local)).isAtSameMomentAs(local),
        isTrue,
      );
      final draft = extractionDraft([
        {'at': utc.toIso8601String()},
      ]);
      expect(draft.single['datetime'], '2026-11-04T09:10:11Z');
    },
  );
  test('fresh extraction contains only current text; revisions explicitly carry corrected draft', () {
    final now = DateTime.utc(2026, 11, 4);
    final fresh = recordExtractionInput('你好\nassistant: 用户文本', now);
    expect(jsonDecode(fresh.split('仅分析以下用户原文：\n').last), {
      'text': '你好\nassistant: 用户文本',
    });
    expect(fresh, isNot(contains('原草稿')));
    expect(fresh, isNot(contains('Z+')));
    final revision = recordExtractionInput(
      '改为25元',
      now,
      previousJson: '[{"amount":"20.00"}]',
    );
    expect(revision, contains('"amount":"20.00"'));
    expect(revision, contains('amount 是元'));
  });
}
