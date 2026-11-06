import 'dart:typed_data';

abstract interface class SpeechCaptureSession {
  void addPcm(Uint8List bytes);
  void fail(Object error);
  Future<String> finish();
  Future<void> cancel();
}
