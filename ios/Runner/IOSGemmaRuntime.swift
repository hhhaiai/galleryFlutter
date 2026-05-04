import Flutter
import Foundation
import UIKit

final class IOSGemmaRuntime: NSObject {
  private let methodChannelName = "com.example.gemma_local_app/runtime"
  private let eventChannelName = "com.example.gemma_local_app/runtime_events"
  private var eventSink: FlutterEventSink?

  func register(with messenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "prepareVisionImage":
        self.prepareVisionImage(call: call, result: result)
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

  private func prepareVisionImage(call: FlutterMethodCall, result: FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let imagePath = args["imagePath"] as? String,
          !imagePath.isEmpty else {
      result(FlutterError(
        code: "BAD_ARGS",
        message: "prepareVisionImage requires a non-empty imagePath.",
        details: nil
      ))
      return
    }

    let requestedMaxDimension = args["maxDimension"] as? Int ?? 1024
    let maxDimension = max(1, requestedMaxDimension)
    guard FileManager.default.fileExists(atPath: imagePath) else {
      result(FlutterError(
        code: "IMAGE_NOT_FOUND",
        message: "Image file not found: \(imagePath)",
        details: nil
      ))
      return
    }
    guard let sourceImage = UIImage(contentsOfFile: imagePath) else {
      result(FlutterError(
        code: "IMAGE_DECODE_FAILED",
        message: "Unable to decode image: \(imagePath)",
        details: nil
      ))
      return
    }

    let sourceSize = sourceImage.size
    guard sourceSize.width > 0, sourceSize.height > 0 else {
      result(FlutterError(
        code: "IMAGE_SIZE_INVALID",
        message: "Decoded image has invalid size: \(sourceSize.width)x\(sourceSize.height)",
        details: nil
      ))
      return
    }

    let longestSide = max(sourceSize.width, sourceSize.height)
    let scale: CGFloat
    if longestSide > CGFloat(maxDimension) {
      scale = CGFloat(maxDimension) / longestSide
    } else {
      scale = 1.0
    }
    let targetSize = CGSize(
      width: CGFloat(max(1, Int((sourceSize.width * scale).rounded()))),
      height: CGFloat(max(1, Int((sourceSize.height * scale).rounded())))
    )
    let rendererFormat = UIGraphicsImageRendererFormat()
    rendererFormat.scale = 1
    rendererFormat.opaque = false
    let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
    let normalizedImage = renderer.image { _ in
      sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
    }
    guard let pngData = normalizedImage.pngData(), !pngData.isEmpty else {
      result(FlutterError(
        code: "IMAGE_ENCODE_FAILED",
        message: "Unable to encode normalized image as PNG.",
        details: nil
      ))
      return
    }
    result(FlutterStandardTypedData(bytes: pngData))
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
