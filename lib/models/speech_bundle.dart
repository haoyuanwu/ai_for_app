import 'dart:io';

/// Local file contracts for the speech runtimes; no network access.
class SpeechBundle {
  const SpeechBundle(this.path, this.format);
  final String path, format;

  static List<String> filesFor(String format) => switch (format) {
    'sensevoice' => ['model.int8.onnx', 'tokens.txt'],
    'qwen3asr' => [
      'conv_frontend.onnx',
      'encoder.int8.onnx',
      'decoder.int8.onnx',
      'tokenizer/merges.txt',
      'tokenizer/vocab.json',
      'tokenizer/tokenizer_config.json',
    ],
    _ => throw const FormatException('不支持的本地语音模型格式'),
  };

  static Future<SpeechBundle> detect(Directory directory) async {
    final candidates = <SpeechBundle>[];
    await for (final entry in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is! File) continue;
      final root = entry.parent.path;
      final name = entry.uri.pathSegments.last;
      if (name == 'model.int8.onnx' || name == 'conv_frontend.onnx') {
        final format = name == 'model.int8.onnx' ? 'sensevoice' : 'qwen3asr';
        var complete = true;
        for (final file in filesFor(format)) {
          final local = File('$root/$file');
          if (!await local.exists() || await local.length() == 0) {
            complete = false;
            break;
          }
        }
        if (complete) candidates.add(SpeechBundle(root, format));
      } else if (name == 'config.json' &&
          await Directory('$root/onnx').exists()) {
        final hasWeights = await Directory('$root/onnx')
            .list()
            .any((f) => f is File && f.path.endsWith('.onnx'));
        if (hasWeights) candidates.add(SpeechBundle(root, 'whisper'));
      }
    }
    if (candidates.length != 1) {
      throw const FormatException(
        'ZIP 需包含且仅包含一套完整语音模型：SenseVoice、Qwen3-ASR sherpa-onnx 或 Whisper ONNX。请保留原始文件名和目录结构。',
      );
    }
    return candidates.single;
  }
}
