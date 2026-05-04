import AVFoundation
import Flutter
import UIKit
import UniformTypeIdentifiers

final class IOSAudioInput: NSObject, UIDocumentPickerDelegate, AVAudioRecorderDelegate, FlutterStreamHandler {
  private let channelName = "com.example.gemma_local_app/audio_input"
  private let eventChannelName = "com.example.gemma_local_app/audio_input_events"
  private let sampleRate: Double = 16_000
  private let maxAudioSeconds: TimeInterval = 30
  private let meterPushInterval: TimeInterval = 0.12
  private var pendingPickResult: FlutterResult?
  private var recorder: AVAudioRecorder?
  private var recordingURL: URL?
  private var recordingStartedAt: Date?
  private var player: AVAudioPlayer?
  private var eventSink: FlutterEventSink?
  private var meterTimer: Timer?

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "pickAudioFile":
        self.pickAudioFile(result: result)
      case "startRecording":
        self.startRecording(result: result)
      case "stopRecording":
        self.stopRecording(result: result)
      case "cancelRecording":
        self.cancelRecording(result: result)
      case "playAudio":
        self.playAudio(call: call, result: result)
      case "stopPlayback":
        self.stopPlayback(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    eventChannel.setStreamHandler(self)
  }

  private func pickAudioFile(result: @escaping FlutterResult) {
    guard pendingPickResult == nil else {
      result(FlutterError(code: "PICK_IN_PROGRESS", message: "Another audio picker is already open.", details: nil))
      return
    }
    pendingPickResult = result
    DispatchQueue.main.async {
      let picker: UIDocumentPickerViewController
      if #available(iOS 14.0, *) {
        picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio], asCopy: true)
      } else {
        picker = UIDocumentPickerViewController(documentTypes: ["public.audio"], in: .import)
      }
      picker.delegate = self
      picker.allowsMultipleSelection = false
      guard let controller = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows })
        .first(where: { $0.isKeyWindow })?
        .rootViewController else {
        self.finishPick(nil)
        return
      }
      controller.present(picker, animated: true)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishPick(nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let source = urls.first else {
      finishPick(nil)
      return
    }
    do {
      let shouldStop = source.startAccessingSecurityScopedResource()
      defer {
        if shouldStop { source.stopAccessingSecurityScopedResource() }
      }
      let destination = try preparePickedAudioForGemma(source)
      finishPick(audioMap(destination, durationMs: readDurationMs(destination)))
    } catch {
      finishPick(FlutterError(code: "PICK_AUDIO_FAILED", message: error.localizedDescription, details: nil))
    }
  }

  private func finishPick(_ value: Any?) {
    let result = pendingPickResult
    pendingPickResult = nil
    result?(value)
  }

  private func startRecording(result: @escaping FlutterResult) {
    if recorder != nil {
      result(FlutterError(code: "ALREADY_RECORDING", message: "Audio recording is already running.", details: nil))
      return
    }
    AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
      guard let self else { return }
      DispatchQueue.main.async {
        guard granted else {
          result(FlutterError(code: "MIC_PERMISSION_REQUIRED", message: "请授权麦克风权限后重试。", details: nil))
          return
        }
        do {
          let session = AVAudioSession.sharedInstance()
          try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
          try session.setActive(true)
          let url = self.cacheURL(prefix: "voice", ext: "wav")
          let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
          ]
          let recorder = try AVAudioRecorder(url: url, settings: settings)
          recorder.delegate = self
          recorder.isMeteringEnabled = true
          recorder.prepareToRecord()
          recorder.record(forDuration: self.maxAudioSeconds)
          self.recorder = recorder
          self.recordingURL = url
          self.recordingStartedAt = Date()
          self.emitAudioEvent(["type": "recording", "state": "started"])
          self.startMeteringTimer()
          result(nil)
        } catch {
          result(FlutterError(code: "RECORD_START_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func stopRecording(result: @escaping FlutterResult) {
    guard let url = recordingURL else {
      result(nil)
      return
    }
    stopMeteringTimer()
    recorder?.stop()
    self.recorder = nil
    self.recordingURL = nil
    let elapsed = recordingStartedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? readDurationMs(url)
    recordingStartedAt = nil
    emitAudioEvent(["type": "recording", "state": "stopped"])
    do {
      try validateGemmaWav(url)
      result(audioMap(url, durationMs: max(1000, elapsed)))
    } catch {
      result(FlutterError(code: "INVALID_RECORDING", message: error.localizedDescription, details: nil))
    }
  }

  private func cancelRecording(result: @escaping FlutterResult) {
    stopMeteringTimer()
    recorder?.stop()
    recorder = nil
    if let url = recordingURL {
      try? FileManager.default.removeItem(at: url)
    }
    recordingURL = nil
    recordingStartedAt = nil
    emitAudioEvent(["type": "recording", "state": "cancelled"])
    result(nil)
  }

  private func playAudio(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
      result(FlutterError(code: "PATH_REQUIRED", message: "path is required", details: nil))
      return
    }
    do {
      player?.stop()
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio)
      try session.setActive(true)
      let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
      player.prepareToPlay()
      player.play()
      self.player = player
      result(nil)
    } catch {
      result(FlutterError(code: "PLAY_AUDIO_FAILED", message: error.localizedDescription, details: nil))
    }
  }

  private func stopPlayback(result: @escaping FlutterResult) {
    player?.stop()
    player = nil
    result(nil)
  }

  func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
    stopMeteringTimer()
    self.recorder = nil
    emitAudioEvent(["type": "recording", "state": flag ? "stopped" : "failed"])
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func cacheURL(prefix: String, ext: String) -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("\(prefix)_\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)")
  }

  private func readDurationMs(_ url: URL) -> Int {
    let asset = AVURLAsset(url: url)
    let seconds = CMTimeGetSeconds(asset.duration)
    guard seconds.isFinite, seconds > 0 else { return 0 }
    return Int(seconds * 1000)
  }

  private func audioMap(_ url: URL, durationMs: Int) -> [String: Any] {
    [
      "path": url.path,
      "durationMs": durationMs,
      "waveform": estimateWaveform(url),
    ]
  }

  private func estimateWaveform(_ url: URL) -> [Double] {
    guard let data = try? Data(contentsOf: url),
          let samples = readWavPCM16Samples(data),
          !samples.isEmpty else {
      return (0..<18).map { 0.28 + Double($0 % 4) * 0.12 }
    }
    let bucketCount = 24
    let bucketSize = max(1, samples.count / bucketCount)
    return (0..<bucketCount).map { bucket in
      let start = bucket * bucketSize
      let end = min(samples.count, start + bucketSize)
      if start >= end { return 0.08 }
      var sum = 0
      for index in start..<end {
        sum += abs(Int(samples[index]))
      }
      return min(1.0, max(0.08, Double(sum) / Double(end - start) / 32767.0))
    }
  }

  private func emitAudioEvent(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(event)
    }
  }

  private func startMeteringTimer() {
    stopMeteringTimer()
    let timer = Timer(timeInterval: meterPushInterval, repeats: true) { [weak self] _ in
      guard let self, let recorder = self.recorder else { return }
      recorder.updateMeters()
      let power = recorder.averagePower(forChannel: 0)
      let amplitude = power <= -80 ? 0 : pow(10.0, Double(power) / 20.0)
      let elapsedMs = self.recordingStartedAt.map {
        Int(Date().timeIntervalSince($0) * 1000)
      } ?? 0
      self.emitAudioEvent([
        "type": "level",
        "amplitude": min(1.0, max(0.0, amplitude)),
        "elapsedMs": max(0, elapsedMs),
      ])
    }
    RunLoop.main.add(timer, forMode: .common)
    meterTimer = timer
  }

  private func stopMeteringTimer() {
    meterTimer?.invalidate()
    meterTimer = nil
  }

  private func preparePickedAudioForGemma(_ source: URL) throws -> URL {
    let destination = cacheURL(prefix: "picked_audio", ext: "wav")
    try normalizeAudioFileToGemmaWav(source, destination: destination)
    try validateGemmaWav(destination)
    return destination
  }

  private func normalizeAudioFileToGemmaWav(_ source: URL, destination: URL) throws {
    let inputFile = try AVAudioFile(forReading: source)
    let inputFormat = inputFile.processingFormat
    let maxSourceFrames = min(
      inputFile.length,
      AVAudioFramePosition(inputFormat.sampleRate * maxAudioSeconds)
    )
    guard maxSourceFrames > 0 else {
      throw NSError(domain: "IOSAudioInput", code: 1001, userInfo: [NSLocalizedDescriptionKey: "音频文件为空。"])
    }
    guard let inputBuffer = AVAudioPCMBuffer(
      pcmFormat: inputFormat,
      frameCapacity: AVAudioFrameCount(maxSourceFrames)
    ) else {
      throw NSError(domain: "IOSAudioInput", code: 1002, userInfo: [NSLocalizedDescriptionKey: "无法创建音频输入缓冲区。"])
    }
    try inputFile.read(into: inputBuffer, frameCount: AVAudioFrameCount(maxSourceFrames))
    guard inputBuffer.frameLength > 0 else {
      throw NSError(domain: "IOSAudioInput", code: 1003, userInfo: [NSLocalizedDescriptionKey: "音频文件没有可解码的 PCM 数据。"])
    }
    guard let targetFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: sampleRate,
      channels: 1,
      interleaved: true
    ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
      throw NSError(domain: "IOSAudioInput", code: 1004, userInfo: [NSLocalizedDescriptionKey: "无法创建 16k mono PCM 转换器。"])
    }

    let ratio = sampleRate / inputFormat.sampleRate
    let targetCapacity = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio)) + 1024
    guard let outputBuffer = AVAudioPCMBuffer(
      pcmFormat: targetFormat,
      frameCapacity: targetCapacity
    ) else {
      throw NSError(domain: "IOSAudioInput", code: 1005, userInfo: [NSLocalizedDescriptionKey: "无法创建音频输出缓冲区。"])
    }

    var didProvideInput = false
    var conversionError: NSError?
    let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
      if didProvideInput {
        outStatus.pointee = .noDataNow
        return nil
      }
      didProvideInput = true
      outStatus.pointee = .haveData
      return inputBuffer
    }
    if status == .error {
      throw conversionError ?? NSError(domain: "IOSAudioInput", code: 1006, userInfo: [NSLocalizedDescriptionKey: "音频转换失败。"])
    }
    guard outputBuffer.frameLength > 0 else {
      throw NSError(domain: "IOSAudioInput", code: 1007, userInfo: [NSLocalizedDescriptionKey: "转换后音频为空。"])
    }

    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    let outputFile = try AVAudioFile(
      forWriting: destination,
      settings: targetFormat.settings,
      commonFormat: .pcmFormatInt16,
      interleaved: true
    )
    try outputFile.write(from: outputBuffer)
  }

  private func validateGemmaWav(_ url: URL) throws {
    let data = try Data(contentsOf: url)
    guard data.count >= 44 else {
      throw NSError(domain: "IOSAudioInput", code: 1101, userInfo: [NSLocalizedDescriptionKey: "WAV 文件太小。"])
    }
    guard ascii(data, 0, 4) == "RIFF", ascii(data, 8, 4) == "WAVE" else {
      throw NSError(domain: "IOSAudioInput", code: 1102, userInfo: [NSLocalizedDescriptionKey: "不是有效的 RIFF/WAVE 文件。"])
    }
    // Walk chunks instead of assuming fixed offsets — AVAudioRecorder may
    // write extra chunks (fact, LIST, …) before fmt / data.
    var offset = 12
    var audioFormat: UInt16 = 0
    var channels: UInt16 = 0
    var rate: UInt32 = 0
    var bits: UInt16 = 0
    var foundFmt = false
    while offset + 8 <= data.count {
      let chunkId = ascii(data, offset, 4)
      let chunkSize = Int(littleUInt32(data, offset + 4))
      let chunkDataOffset = offset + 8
      guard chunkSize >= 0, chunkDataOffset + chunkSize <= data.count else { break }
      if chunkId == "fmt " {
        guard chunkSize >= 16 else {
          throw NSError(domain: "IOSAudioInput", code: 1103, userInfo: [NSLocalizedDescriptionKey: "WAV fmt chunk 太小。"])
        }
        audioFormat = littleUInt16(data, chunkDataOffset)
        channels = littleUInt16(data, chunkDataOffset + 2)
        rate = littleUInt32(data, chunkDataOffset + 4)
        bits = littleUInt16(data, chunkDataOffset + 14)
        foundFmt = true
      } else if chunkId == "data" {
        break
      }
      offset = chunkDataOffset + chunkSize + (chunkSize & 1)
    }
    guard foundFmt else {
      throw NSError(domain: "IOSAudioInput", code: 1103, userInfo: [NSLocalizedDescriptionKey: "WAV 文件缺少 fmt chunk。"])
    }
    guard audioFormat == 1 || audioFormat == 0xFFFE else {
      throw NSError(domain: "IOSAudioInput", code: 1103, userInfo: [NSLocalizedDescriptionKey: "WAV 必须是 PCM 格式。"])
    }
    guard channels == 1, rate == UInt32(sampleRate), bits == 16 else {
      throw NSError(
        domain: "IOSAudioInput",
        code: 1104,
        userInfo: [NSLocalizedDescriptionKey: "WAV 必须是 16kHz / mono / 16-bit PCM。当前 channels=\(channels), sampleRate=\(rate), bits=\(bits)。"]
      )
    }
    let maxBytes = Int(sampleRate * maxAudioSeconds * 2) + 44
    guard data.count <= maxBytes + 4096 else {
      throw NSError(domain: "IOSAudioInput", code: 1105, userInfo: [NSLocalizedDescriptionKey: "音频超过 30 秒上限。"])
    }
  }

  private func readWavPCM16Samples(_ data: Data) -> [Int16]? {
    guard data.count >= 44, ascii(data, 0, 4) == "RIFF", ascii(data, 8, 4) == "WAVE" else {
      return nil
    }
    var offset = 12
    var audioFormat: UInt16 = 1
    var channels: UInt16 = 1
    var bitsPerSample: UInt16 = 16
    var dataOffset = -1
    var dataSize = 0
    while offset + 8 <= data.count {
      let chunkId = ascii(data, offset, 4)
      let chunkSize = Int(littleUInt32(data, offset + 4))
      let chunkDataOffset = offset + 8
      guard chunkSize >= 0, chunkDataOffset + chunkSize <= data.count else {
        break
      }
      if chunkId == "fmt " {
        guard chunkSize >= 16 else { return nil }
        audioFormat = littleUInt16(data, chunkDataOffset)
        channels = max(1, littleUInt16(data, chunkDataOffset + 2))
        bitsPerSample = littleUInt16(data, chunkDataOffset + 14)
      } else if chunkId == "data" {
        dataOffset = chunkDataOffset
        dataSize = chunkSize
        break
      }
      offset = chunkDataOffset + chunkSize + (chunkSize & 1)
    }
    guard (audioFormat == 1 || audioFormat == 0xFFFE),
          bitsPerSample == 16,
          dataOffset >= 0,
          dataSize > 1 else {
      return nil
    }

    var interleaved: [Int16] = []
    interleaved.reserveCapacity(dataSize / 2)
    var index = dataOffset
    while index + 1 < dataOffset + dataSize {
      interleaved.append(Int16(bitPattern: littleUInt16(data, index)))
      index += 2
    }
    if channels <= 1 {
      return interleaved
    }
    let channelCount = Int(channels)
    let frames = interleaved.count / channelCount
    return (0..<frames).map { frame in
      var sum = 0
      for channel in 0..<channelCount {
        sum += Int(interleaved[frame * channelCount + channel])
      }
      return Int16(sum / channelCount)
    }
  }

  private func ascii(_ data: Data, _ offset: Int, _ count: Int) -> String {
    guard offset + count <= data.count else { return "" }
    return String(data: data.subdata(in: offset..<(offset + count)), encoding: .ascii) ?? ""
  }

  private func littleUInt16(_ data: Data, _ offset: Int) -> UInt16 {
    guard offset + 1 < data.count else { return 0 }
    return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
  }

  private func littleUInt32(_ data: Data, _ offset: Int) -> UInt32 {
    guard offset + 3 < data.count else { return 0 }
    return UInt32(data[offset])
      | (UInt32(data[offset + 1]) << 8)
      | (UInt32(data[offset + 2]) << 16)
      | (UInt32(data[offset + 3]) << 24)
  }
}
