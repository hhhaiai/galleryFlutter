import Flutter
import Foundation
import UIKit
import Darwin

private final class LiteRtLmSymbols {
  typealias EngineSettingsCreate = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> OpaquePointer?
  typealias EngineSettingsDelete = @convention(c) (OpaquePointer?) -> Void
  typealias EngineSettingsSetMaxTokens = @convention(c) (OpaquePointer?, Int32) -> Void
  typealias EngineSettingsSetCacheDir = @convention(c) (OpaquePointer?, UnsafePointer<CChar>) -> Void
  typealias EngineCreate = @convention(c) (OpaquePointer?) -> OpaquePointer?
  typealias EngineDelete = @convention(c) (OpaquePointer?) -> Void
  typealias SessionConfigCreate = @convention(c) () -> OpaquePointer?
  typealias SessionConfigSetMaxTokens = @convention(c) (OpaquePointer?, Int32) -> Void
  typealias SessionConfigSetSamplerParams = @convention(c) (OpaquePointer?, UnsafePointer<LiteRtLmSamplerParamsC>) -> Void
  typealias SessionConfigDelete = @convention(c) (OpaquePointer?) -> Void
  typealias EngineCreateSession = @convention(c) (OpaquePointer?, OpaquePointer?) -> OpaquePointer?
  typealias SessionDelete = @convention(c) (OpaquePointer?) -> Void
  typealias SessionCancel = @convention(c) (OpaquePointer?) -> Void
  typealias SessionGenerateContent = @convention(c) (OpaquePointer?, UnsafePointer<LiteRtLmInputDataC>, Int) -> OpaquePointer?
  typealias ResponsesDelete = @convention(c) (OpaquePointer?) -> Void
  typealias ResponsesGetNumCandidates = @convention(c) (OpaquePointer?) -> Int32
  typealias ResponsesGetResponseTextAt = @convention(c) (OpaquePointer?, Int32) -> UnsafePointer<CChar>?

  let handle: UnsafeMutableRawPointer
  let engineSettingsCreate: EngineSettingsCreate
  let engineSettingsDelete: EngineSettingsDelete
  let engineSettingsSetMaxTokens: EngineSettingsSetMaxTokens
  let engineSettingsSetCacheDir: EngineSettingsSetCacheDir
  let engineCreate: EngineCreate
  let engineDelete: EngineDelete
  let sessionConfigCreate: SessionConfigCreate
  let sessionConfigSetMaxTokens: SessionConfigSetMaxTokens
  let sessionConfigSetSamplerParams: SessionConfigSetSamplerParams
  let sessionConfigDelete: SessionConfigDelete
  let engineCreateSession: EngineCreateSession
  let sessionDelete: SessionDelete
  let sessionCancel: SessionCancel
  let sessionGenerateContent: SessionGenerateContent
  let responsesDelete: ResponsesDelete
  let responsesGetNumCandidates: ResponsesGetNumCandidates
  let responsesGetResponseTextAt: ResponsesGetResponseTextAt

  init() throws {
    Self.preloadFramework("GemmaModelConstraintProvider")
    Self.preloadFramework("LiteRtMetalAccelerator")
    Self.preloadFramework("LiteRtTopKMetalSampler")
    guard let liteHandle = Self.preloadFramework("LiteRtLm") else {
      throw NSError(domain: "IOSGemmaRuntime", code: 1, userInfo: [NSLocalizedDescriptionKey: "dlopen LiteRtLm.framework failed"])
    }
    handle = liteHandle
    engineSettingsCreate = try Self.sym(handle, "litert_lm_engine_settings_create")
    engineSettingsDelete = try Self.sym(handle, "litert_lm_engine_settings_delete")
    engineSettingsSetMaxTokens = try Self.sym(handle, "litert_lm_engine_settings_set_max_num_tokens")
    engineSettingsSetCacheDir = try Self.sym(handle, "litert_lm_engine_settings_set_cache_dir")
    engineCreate = try Self.sym(handle, "litert_lm_engine_create")
    engineDelete = try Self.sym(handle, "litert_lm_engine_delete")
    sessionConfigCreate = try Self.sym(handle, "litert_lm_session_config_create")
    sessionConfigSetMaxTokens = try Self.sym(handle, "litert_lm_session_config_set_max_output_tokens")
    sessionConfigSetSamplerParams = try Self.sym(handle, "litert_lm_session_config_set_sampler_params")
    sessionConfigDelete = try Self.sym(handle, "litert_lm_session_config_delete")
    engineCreateSession = try Self.sym(handle, "litert_lm_engine_create_session")
    sessionDelete = try Self.sym(handle, "litert_lm_session_delete")
    sessionCancel = try Self.sym(handle, "litert_lm_session_cancel_process")
    sessionGenerateContent = try Self.sym(handle, "litert_lm_session_generate_content")
    responsesDelete = try Self.sym(handle, "litert_lm_responses_delete")
    responsesGetNumCandidates = try Self.sym(handle, "litert_lm_responses_get_num_candidates")
    responsesGetResponseTextAt = try Self.sym(handle, "litert_lm_responses_get_response_text_at")
  }

  @discardableResult
  private static func preloadFramework(_ name: String) -> UnsafeMutableRawPointer? {
    let candidates = [
      "@executable_path/Frameworks/\(name).framework/\(name)",
      Bundle.main.privateFrameworksURL?.appendingPathComponent("\(name).framework/\(name)").path,
    ].compactMap { $0 }
    for path in candidates {
      if let handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL) {
        NSLog("[GemmaIOSNative] dlopen \(name) ok: \(path)")
        return handle
      }
    }
    if let err = dlerror() {
      NSLog("[GemmaIOSNative] dlopen \(name) failed: \(String(cString: err))")
    }
    return nil
  }

  private static func sym<T>(_ handle: UnsafeMutableRawPointer, _ name: String) throws -> T {
    guard let pointer = dlsym(handle, name) else {
      throw NSError(domain: "IOSGemmaRuntime", code: 2, userInfo: [NSLocalizedDescriptionKey: "missing LiteRT-LM symbol: \(name)"])
    }
    return unsafeBitCast(pointer, to: T.self)
  }
}

final class IOSGemmaRuntime: NSObject {
  private let methodChannelName = "com.example.gemma_local_app/runtime"
  private let eventChannelName = "com.example.gemma_local_app/runtime_events"
  private let inferenceQueue = DispatchQueue(label: "com.example.gemma_local_app.ios_gemma_runtime")
  private var eventSink: FlutterEventSink?
  private var modelPath: String?
  private var topK: Int32 = 64
  private var topP: Float = 0.95
  private var temperature: Float = 0.1
  private var maxTokens: Int32 = 1024
  private var activeSession: OpaquePointer?
  private lazy var symbols: LiteRtLmSymbols? = try? LiteRtLmSymbols()

  func register(with messenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "prepareVisionImage":
        self.prepareVisionImage(call: call, result: result)
      case "getDeviceMemoryInfo":
        self.getDeviceMemoryInfo(result: result)
      case "initialize":
        self.initialize(call: call, result: result)
      case "generate":
        self.generate(call: call, result: result)
      case "stop":
        self.stop(result: result)
      case "dispose":
        self.disposeRuntime(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    eventChannel.setStreamHandler(IOSGemmaRuntimeStreamHandler(runtime: self))
  }

  private func initialize(call: FlutterMethodCall, result: FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    guard let path = args["modelPath"] as? String, !path.isEmpty else {
      result(FlutterError(code: "BAD_ARGS", message: "initialize requires modelPath", details: nil))
      return
    }
    guard FileManager.default.fileExists(atPath: path) else {
      result(FlutterError(code: "MODEL_NOT_FOUND", message: "Model file not found: \(path)", details: nil))
      return
    }
    modelPath = path
    topK = Int32(args["topK"] as? Int ?? 64)
    topP = Float(args["topP"] as? Double ?? 0.95)
    temperature = Float(args["temperature"] as? Double ?? 0.1)
    maxTokens = Int32(args["maxTokens"] as? Int ?? 1024)
    result(nil)
  }

  private func generate(call: FlutterMethodCall, result: FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let prompt = args["prompt"] as? String ?? ""
    let audioPaths = args["audioPaths"] as? [String] ?? []
    guard let path = modelPath else {
      result(FlutterError(code: "NOT_INITIALIZED", message: "iOS native Gemma runtime is not initialized", details: nil))
      return
    }
    result(nil)
    inferenceQueue.async { [weak self] in
      guard let self else { return }
      do {
        let output = try self.generateDirect(modelPath: path, prompt: prompt, audioPaths: audioPaths)
        self.emit(["type": "token", "text": output])
        self.emit(["type": "done"])
      } catch {
        self.emit(["type": "error", "message": "iOS native LiteRT-LM direct session failed: \(error.localizedDescription)"])
      }
    }
  }

  private func stop(result: FlutterResult) {
    if let session = activeSession, let symbols {
      symbols.sessionCancel(session)
    }
    result(nil)
  }

  private func disposeRuntime(result: FlutterResult) {
    activeSession = nil
    result(nil)
  }

  private func generateDirect(modelPath: String, prompt: String, audioPaths: [String]) throws -> String {
    guard let symbols else {
      throw NSError(domain: "IOSGemmaRuntime", code: 3, userInfo: [NSLocalizedDescriptionKey: "LiteRT-LM symbols are not available"])
    }
    var lastError: Error?
    for backend in audioPaths.isEmpty ? ["gpu", "cpu"] : ["cpu", "gpu"] {
      do {
        return try generateDirectAttempt(symbols: symbols, modelPath: modelPath, backend: backend, prompt: prompt, audioPaths: audioPaths)
      } catch {
        NSLog("[GemmaIOSNative] direct session backend=\(backend) failed: \(error.localizedDescription)")
        lastError = error
      }
    }
    throw lastError ?? NSError(domain: "IOSGemmaRuntime", code: 4, userInfo: [NSLocalizedDescriptionKey: "All native direct session backends failed"])
  }

  private func generateDirectAttempt(symbols: LiteRtLmSymbols, modelPath: String, backend: String, prompt: String, audioPaths: [String]) throws -> String {
    var audioData: Data?
    if let firstAudio = audioPaths.first {
      audioData = try Data(contentsOf: URL(fileURLWithPath: firstAudio))
    }
    let cacheDir = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("litertlm_native_cache", isDirectory: true)
    try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

    return try modelPath.withCString { modelPtr in
      try backend.withCString { backendPtr in
        try "cpu".withCString { audioBackendPtr in
          let settings = symbols.engineSettingsCreate(modelPtr, backendPtr, nil, audioData == nil ? nil : audioBackendPtr)
          guard let settings else { throw NSError(domain: "IOSGemmaRuntime", code: 5, userInfo: [NSLocalizedDescriptionKey: "engine settings create returned null"])}
          defer { symbols.engineSettingsDelete(settings) }
          symbols.engineSettingsSetMaxTokens(settings, maxTokens)
          cacheDir.path.withCString { cachePtr in
            symbols.engineSettingsSetCacheDir(settings, cachePtr)
          }
          guard let engine = symbols.engineCreate(settings) else {
            throw NSError(domain: "IOSGemmaRuntime", code: 6, userInfo: [NSLocalizedDescriptionKey: "engine create returned null for backend \(backend)"])
          }
          defer { symbols.engineDelete(engine) }

          guard let sessionConfig = symbols.sessionConfigCreate() else {
            throw NSError(domain: "IOSGemmaRuntime", code: 7, userInfo: [NSLocalizedDescriptionKey: "session config create returned null"])
          }
          defer { symbols.sessionConfigDelete(sessionConfig) }
          symbols.sessionConfigSetMaxTokens(sessionConfig, maxTokens)
          var sampler = LiteRtLmSamplerParamsC(type: 2, top_k: topK, top_p: topP, temperature: temperature, seed: 1)
          withUnsafePointer(to: &sampler) { samplerPtr in
            symbols.sessionConfigSetSamplerParams(sessionConfig, samplerPtr)
          }

          guard let session = symbols.engineCreateSession(engine, sessionConfig) else {
            throw NSError(domain: "IOSGemmaRuntime", code: 8, userInfo: [NSLocalizedDescriptionKey: "session create returned null"])
          }
          activeSession = session
          defer {
            activeSession = nil
            symbols.sessionDelete(session)
          }

          return try prompt.withCString { promptPtr in
            if let audioData {
              return try audioData.withUnsafeBytes { audioBytes in
                guard let audioBase = audioBytes.baseAddress else {
                  throw NSError(domain: "IOSGemmaRuntime", code: 9, userInfo: [NSLocalizedDescriptionKey: "audio bytes are empty"])
                }
                var inputs = [
                  LiteRtLmInputDataC(type: 3, data: audioBase, size: audioData.count),
                  LiteRtLmInputDataC(type: 0, data: UnsafeRawPointer(promptPtr), size: strlen(promptPtr)),
                ]
                return try runGenerate(symbols: symbols, session: session, inputs: &inputs)
              }
            }
            var inputs = [LiteRtLmInputDataC(type: 0, data: UnsafeRawPointer(promptPtr), size: strlen(promptPtr))]
            return try runGenerate(symbols: symbols, session: session, inputs: &inputs)
          }
        }
      }
    }
  }

  private func runGenerate(symbols: LiteRtLmSymbols, session: OpaquePointer, inputs: inout [LiteRtLmInputDataC]) throws -> String {
    guard let responses = inputs.withUnsafeBufferPointer({ buffer in
      symbols.sessionGenerateContent(session, buffer.baseAddress!, buffer.count)
    }) else {
      throw NSError(domain: "IOSGemmaRuntime", code: 10, userInfo: [NSLocalizedDescriptionKey: "session_generate_content returned null"])
    }
    defer { symbols.responsesDelete(responses) }
    let count = symbols.responsesGetNumCandidates(responses)
    guard count > 0, let textPtr = symbols.responsesGetResponseTextAt(responses, 0) else {
      throw NSError(domain: "IOSGemmaRuntime", code: 11, userInfo: [NSLocalizedDescriptionKey: "empty LiteRT-LM response"])
    }
    return String(cString: textPtr)
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

  private func getDeviceMemoryInfo(result: FlutterResult) {
    let processInfo = ProcessInfo.processInfo
    result([
      "totalMemoryBytes": NSNumber(value: processInfo.physicalMemory),
      "processorCount": NSNumber(value: processInfo.processorCount),
      "activeProcessorCount": NSNumber(value: processInfo.activeProcessorCount),
      "thermalState": NSNumber(value: processInfo.thermalState.rawValue),
      "lowPowerModeEnabled": NSNumber(value: processInfo.isLowPowerModeEnabled),
    ])
  }

  private func emit(_ map: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(map)
    }
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
