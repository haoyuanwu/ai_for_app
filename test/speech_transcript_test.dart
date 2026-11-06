import 'package:ai_for_app/core/speech_transcript.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes ASR wrappers and retains recognized text', () {
    for (final text in [
      '<asr_text>明天见</asr_text>',
      '<|asr_text|>明天见<|endoftext|>',
      'language Chinese<asr_text>明天见',
      '{"asr_text":"明天见"}',
      '<|zh|><|NEUTRAL|><|Speech|><|withitn|>明天见',
    ]) {
      expect(SpeechTranscript.clean(text), '明天见');
    }
    expect(SpeechTranscript.clean('<asr_', partial: true), '');
    expect(SpeechTranscript.clean('<asr_text>你好</asr_', partial: true), '你好');
    expect(SpeechTranscript.clean('{"asr_text":', partial: true), '');
  });
  test('normalizes numeric quantities without rewriting ordinary Chinese', () {
    final cases = {
      '明天九点三十分买三个苹果，花了二十三点五元': '明天9点30分买3个苹果，花了23.5元',
      '二〇二六年十一月五日': '2026年11月5日',
      '电话幺三八零零幺二三四五六': '电话13800123456',
      '零零幺二三四': '001234',
      '一亿三千万元': '130000000元',
      '星期三一起去，一点心意，万一迟到等一下': '星期三一起去，一点心意，万一迟到等一下',
      '花了23.50元': '花了23.50元',
    };
    for (final entry in cases.entries) {
      expect(SpeechTranscript.clean(entry.key), entry.value, reason: entry.key);
    }
  });
}
