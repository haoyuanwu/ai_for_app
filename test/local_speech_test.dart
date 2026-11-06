import 'dart:io';

import 'package:ai_for_app/core/local_speech.dart';
import 'package:ai_for_app/models/speech_bundle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('speech_bundle'),
  );
  tearDown(() => root.delete(recursive: true));
  Future<void> writeFiles(String folder, String format) async {
    for (final name in SpeechBundle.filesFor(format)) {
      final f = File('${root.path}/$folder/$name');
      await f.parent.create(recursive: true);
      await f.writeAsString('fixture');
    }
  }

  test('detects full nested speech bundles and rejects incomplete or ambiguous input', () async {
    await writeFiles('sense', 'sensevoice');
    final sense = await SpeechBundle.detect(root);
    expect(sense.format, 'sensevoice');
    expect(sense.path, '${root.path}/sense');
    await writeFiles('qwen', 'qwen3asr');
    await expectLater(SpeechBundle.detect(root), throwsFormatException);
    await Directory('${root.path}/sense').delete(recursive: true);
    final qwen = await SpeechBundle.detect(root);
    expect(qwen.format, 'qwen3asr');
    await File('${qwen.path}/tokenizer/vocab.json').delete();
    await expectLater(SpeechBundle.detect(root), throwsFormatException);
  });
  test('runtime config uses the installed bundle and remains offline', () {
    final sense = localSpeechConfig(root.path, 'sensevoice');
    expect(sense.model.senseVoice.model, '${root.path}/model.int8.onnx');
    expect(sense.model.tokens, '${root.path}/tokens.txt');
    expect(sense.model.senseVoice.useInverseTextNormalization, isTrue);
    final qwen = localSpeechConfig(root.path, 'qwen3asr');
    expect(qwen.model.qwen3Asr.tokenizer, '${root.path}/tokenizer');
    expect(qwen.model.qwen3Asr.encoder, '${root.path}/encoder.int8.onnx');
    expect(() => localSpeechConfig(root.path, 'mnn'), throwsFormatException);
    expect(
      () => transcribeLocalSpeechSync(root.path, '/missing.wav', 'sensevoice'),
      throwsStateError,
    );
  });
}
