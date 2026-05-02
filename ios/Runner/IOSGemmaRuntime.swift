import Flutter
import Foundation

final class IOSGemmaRuntime: NSObject {
  private let methodChannelName = "com.example.gemma_local_app/runtime"
  private let eventChannelName = "com.example.gemma_local_app/runtime_events"

  private var eventSink: FlutterEventSink?
  private var initializedPath: String?

  func register(with messenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "initialize":
        self.initialize(args: args, result: result)
      case "generate":
        self.generate(args: args, result: result)
      case "stop":
        self.emit(["type": "done"])
        result(nil)
      case "dispose":
        self.initializedPath = nil
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    eventChannel.setStreamHandler(IOSGemmaRuntimeStreamHandler(runtime: self))
  }

  func setEventSink(_ sink: FlutterEventSink?) {
    eventSink = sink
  }

  private func initialize(args: [String: Any], result: @escaping FlutterResult) {
    guard let modelPath = args["modelPath"] as? String, !modelPath.isEmpty else {
      result(FlutterError(code: "IOS_RUNTIME_BAD_ARGS", message: "Missing modelPath", details: nil))
      return
    }
    guard FileManager.default.fileExists(atPath: modelPath) else {
      result(FlutterError(code: "IOS_RUNTIME_MODEL_NOT_FOUND", message: "Model file not found", details: modelPath))
      return
    }
    initializedPath = modelPath
    result(nil)
  }

  private func generate(args: [String: Any], result: @escaping FlutterResult) {
    guard initializedPath != nil else {
      result(FlutterError(code: "IOS_RUNTIME_NOT_INITIALIZED", message: "iOS runtime is not initialized", details: nil))
      return
    }
    result(nil)
    emit([
      "type": "error",
      "message": "iOS 模型文件已就绪，但当前构建机 Xcode 15.0.1 无法链接 MediaPipeTasksGenAI 0.10.35，真实 iOS 推理引擎尚未打入包内。需要升级到更新 Xcode/Swift toolchain 后启用 Podfile 中的 MediaPipeTasksGenAI，并使用 IOSGemmaRuntime 的 LlmInference 实现。"
    ])
  }

  private func emit(_ map: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(map)
    }
  }
}

private final class IOSGemmaRuntimeStreamHandler: NSObject, FlutterStreamHandler {
  private weak var runtime: IOSGemmaRuntime?

  init(runtime: IOSGemmaRuntime) {
    self.runtime = runtime
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    runtime?.setEventSink(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    runtime?.setEventSink(nil)
    return nil
  }
}
