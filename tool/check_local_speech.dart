import 'dart:io';

import 'package:ai_for_app/core/local_speech.dart';

// Run with the project's Dart package config. Models are external inputs.
void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln(
      'Usage: dart run tool/check_local_speech.dart <model-directory> <audio.wav> <sensevoice|qwen3asr>',
    );
    exitCode = 64;
    return;
  }
  final watch = Stopwatch()..start();
  try {
    final text = transcribeLocalSpeechSync(args[0], args[1], args[2]);
    stdout.writeln(text);
    stdout.writeln('Local transcription: ${watch.elapsedMilliseconds} ms');
  } catch (e) {
    stderr.writeln('Local transcription failed: $e');
    exitCode = 1;
  }
}
