import AVFoundation
import Flutter
import Speech

/// Receives record's PCM; owns recognition only, never the microphone.
final class NativeSpeechBridge: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var identifier: Int64?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = NativeSpeechBridge()
    registrar.addMethodCallDelegate(instance, channel: FlutterMethodChannel(
      name: "local_journal/native_speech", binaryMessenger: registrar.messenger()))
    FlutterEventChannel(name: "local_journal/native_speech/events",
      binaryMessenger: registrar.messenger()).setStreamHandler(instance)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let id = (args["id"] as? NSNumber)?.int64Value
    switch call.method {
    case "start":
      guard let id = id else { result(FlutterError(code: "arguments", message: "缺少识别会话", details: nil)); return }
      stop()
      identifier = id
      let begin = { [weak self] in
        DispatchQueue.main.async {
          guard let self = self, self.identifier == id else {
            result(FlutterError(code: "cancelled", message: "识别已取消", details: nil)); return
          }
          guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            self.stop()
            result(FlutterError(code: "permission", message: "需要语音识别权限，请在系统设置中允许", details: nil)); return
          }
          self.start(id: id, path: args["path"] as? String, result: result)
        }
      }
      if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
        SFSpeechRecognizer.requestAuthorization { _ in begin() }
      } else { begin() }
    case "append":
      guard identifier == id, let request = request as? SFSpeechAudioBufferRecognitionRequest,
        let pcm = args["pcm"] as? FlutterStandardTypedData else { result(nil); return }
      let bytes = pcm.data
      let frames = bytes.count / 2
      guard frames > 0, frames <= 32000,
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
        let samples = buffer.floatChannelData?[0] else { result(nil); return }
      buffer.frameLength = AVAudioFrameCount(frames)
      bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        for index in 0..<frames {
          let word = UInt16(raw[index * 2]) | UInt16(raw[index * 2 + 1]) << 8
          samples[index] = Float(Int16(bitPattern: word)) / 32768.0
        }
      }
      request.append(buffer)
      result(nil)
    case "finish":
      if identifier == id { (request as? SFSpeechAudioBufferRecognitionRequest)?.endAudio() }
      result(nil)
    case "cancel":
      if identifier == id { stop() }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func start(id: Int64, path: String?, result: @escaping FlutterResult) {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
      recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
      stop()
      result(FlutterError(code: "unavailable", message: "系统离线语音识别不可用，请在设置中选择本地转写模型", details: nil))
      return
    }
    self.recognizer = recognizer
    let request: SFSpeechRecognitionRequest
    if let path = path {
      guard FileManager.default.fileExists(atPath: path) else {
        stop()
        result(FlutterError(code: "missing_audio", message: "录音文件不存在", details: nil)); return
      }
      request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: path))
    } else { request = SFSpeechAudioBufferRecognitionRequest() }
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = true
    request.taskHint = .dictation
    self.request = request
    task = recognizer.recognitionTask(with: request) { [weak self] speech, error in
      DispatchQueue.main.async {
        guard let self = self, self.identifier == id else { return }
        if let speech = speech {
          self.sink?(["id": id, "type": "text", "text": speech.bestTranscription.formattedString, "final": speech.isFinal])
          if speech.isFinal { self.stop(); return }
        }
        if let error = error {
          self.sink?(["id": id, "type": "error", "message": "系统离线转写失败：\(error.localizedDescription)"])
          self.stop()
        }
      }
    }
    result(nil)
  }

  private func stop() {
    identifier = nil
    (request as? SFSpeechAudioBufferRecognitionRequest)?.endAudio()
    task?.cancel()
    task = nil
    request = nil
    recognizer = nil
  }
}
