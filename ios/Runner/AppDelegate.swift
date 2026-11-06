import BackgroundTasks
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    InferenceBackgroundBridge.shared.registerTasks()
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "InferenceBackgroundBridge") {
      InferenceBackgroundBridge.shared.attach(registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeSpeechBridge") {
      NativeSpeechBridge.register(with: registrar)
    }
  }
}

// CPU inference is eligible for continued processing; no audio/GPU keep-alive.
private final class InferenceBackgroundBridge {
  static let shared = InferenceBackgroundBridge()
  private var channel: FlutterMethodChannel?
  private var active = false
  private var legacyTask: UIBackgroundTaskIdentifier = .invalid
  private var continued: AnyObject?
  private let taskID = (Bundle.main.bundleIdentifier ?? "com.example.aiForApp") + ".inference"
  private var observers: [NSObjectProtocol] = []

  func registerTasks() {
    if #available(iOS 26.0, *) {
      BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: .main) { [weak self] task in
        guard let self, let processing = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
        guard self.active else { processing.setTaskCompleted(success: true); return }
        self.continued = processing
        processing.progress.totalUnitCount = 1024
        processing.expirationHandler = { [weak self, weak processing] in
          DispatchQueue.main.async {
            self?.notifyExpiration()
            processing?.setTaskCompleted(success: false)
            self?.continued = nil
          }
        }
        self.finishLegacy()
      }
    }
    observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      self?.channel?.invokeMethod("resumed", arguments: nil)
    })
    observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self, self.active else { return }
      if self.continued == nil && self.legacyTask == .invalid { self.notifyExpiration() }
    })
  }
  func attach(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "ai_for_app/background_execution", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterError(code: "unavailable", message: "后台服务不可用", details: nil)); return }
      switch call.method {
      case "begin": self.begin(); result(nil)
      case "end": self.end(); result(nil)
      case "progress":
        if #available(iOS 26.0, *), let task = self.continued as? BGContinuedProcessingTask {
          task.progress.completedUnitCount += 1
          task.progress.totalUnitCount = max(1024, task.progress.completedUnitCount + 256)
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  private func notifyExpiration() {
    guard active else { return }
    channel?.invokeMethod(UIApplication.shared.applicationState == .active ? "resumed" : "expired", arguments: nil)
  }
  private func begin() {
    guard !active else { return }
    active = true
    if UIApplication.shared.applicationState == .background {
      channel?.invokeMethod("expired", arguments: nil)
      return
    }
    legacyTask = UIApplication.shared.beginBackgroundTask(withName: "本地模型推理") { [weak self] in
      guard let self else { return }
      if self.continued == nil { self.notifyExpiration() }
      self.finishLegacy()
    }
    if #available(iOS 26.0, *) {
      let request = BGContinuedProcessingTaskRequest(identifier: taskID, title: "本地 AI 正在处理", subtitle: "处理对话和图片，完成后自动结束")
      request.strategy = .fail
      // CPU only. Background GPU requires separate device support and entitlement.
      do { try BGTaskScheduler.shared.submit(request) } catch {
        // Legacy grant still permits finishing short work on older/constrained devices.
        if legacyTask == .invalid { channel?.invokeMethod("expired", arguments: nil) }
      }
    }
  }
  private func finishLegacy() {
    if legacyTask != .invalid {
      UIApplication.shared.endBackgroundTask(legacyTask)
      legacyTask = .invalid
    }
  }
  private func end() {
    active = false
    if #available(iOS 26.0, *) {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
      if let task = continued as? BGContinuedProcessingTask {
        task.progress.completedUnitCount = task.progress.totalUnitCount
        task.setTaskCompleted(success: true)
      }
    }
    continued = nil
    finishLegacy()
  }
}
