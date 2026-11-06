import 'dart:io';
import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../models/speech_bundle.dart';

sherpa.OfflineRecognizerConfig localSpeechConfig(String root, String format) {
  final model = switch (format) {
    'sensevoice' => sherpa.OfflineModelConfig(
      senseVoice: sherpa.OfflineSenseVoiceModelConfig(
        model: '$root/model.int8.onnx',
        language: 'auto',
        useInverseTextNormalization: true,
      ),
      tokens: '$root/tokens.txt',
      numThreads: 2,
      debug: false,
    ),
    'qwen3asr' => sherpa.OfflineModelConfig(
      qwen3Asr: sherpa.OfflineQwen3AsrModelConfig(
        convFrontend: '$root/conv_frontend.onnx',
        encoder: '$root/encoder.int8.onnx',
        decoder: '$root/decoder.int8.onnx',
        tokenizer: '$root/tokenizer',
        maxNewTokens: 512,
      ),
      tokens: '',
      numThreads: 2,
      debug: false,
    ),
    _ => throw const FormatException('不支持的本地语音模型格式'),
  };
  return sherpa.OfflineRecognizerConfig(model: model);
}

/// Runs model loading and decoding away from the UI isolate. No model is bundled.
Future<String> transcribeLocalSpeech(
  String root,
  String audio,
  String format,
) => Isolate.run(() => transcribeLocalSpeechSync(root, audio, format));

/// Synchronous worker, also usable for native smoke checks outside a mobile app.
String transcribeLocalSpeechSync(String root, String audio, String format) {
  for (final name in SpeechBundle.filesFor(format)) {
    final file = File('$root/$name');
    if (!file.existsSync() || file.lengthSync() == 0) {
      throw StateError('语音模型文件缺失：$name，请重新下载或导入');
    }
  }
  if (!File(audio).existsSync()) throw StateError('录音文件不存在');
  sherpa.initBindings();
  final wave = sherpa.readWave(audio);
  if (wave.samples.isEmpty || wave.sampleRate <= 0) {
    throw const FormatException('无法读取录音，请使用单声道 WAV 音频');
  }
  final recognizer = sherpa.OfflineRecognizer(localSpeechConfig(root, format));
  try {
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
      recognizer.decode(stream);
      final text = recognizer.getResult(stream).text.trim();
      if (text.isEmpty) throw StateError('未识别到语音，请靠近麦克风重试');
      return text;
    } finally {
      stream.free();
    }
  } finally {
    recognizer.free();
  }
}
