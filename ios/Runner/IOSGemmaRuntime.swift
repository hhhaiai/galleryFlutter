import Flutter
import Foundation

final class IOSGemmaRuntime: NSObject {
  private let methodChannelName = "com.example.gemma_local_app/runtime"
  private let eventChannelName = "com.example.gemma_local_app/runtime_events"
  private var eventSink: FlutterEventSink?

  func register(with messenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "initialize", "generate", "stop", "dispose":
        result(FlutterError(
          code: "IOS_NATIVE_MEDIAPIPE_DISABLED",
          message: "iOS native MediaPipe runtime is disabled; Dart uses flutter_gemma LiteRT-LM FFI for .litertlm models.",
          details: nil
        ))
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
