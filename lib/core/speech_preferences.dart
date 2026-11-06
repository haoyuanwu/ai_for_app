import 'package:flutter/foundation.dart';

class SpeechPreferences {
  static bool useNative(Map<String, dynamic> data) =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS &&
      data['speechTranscriber'] != 'model';
  static bool liveEnabled(Map<String, dynamic> data) =>
      useNative(data) || data['liveSpeechEnabled'] == true;
}
