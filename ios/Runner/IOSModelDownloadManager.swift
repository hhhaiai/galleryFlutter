import Flutter
import Foundation

final class IOSModelDownloadManager: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
  private let methodChannelName = "com.example.gemma_local_app/model_download"
  private let eventChannelName = "com.example.gemma_local_app/model_download_events"
  private let tmpExt = "gallerytmp"
  private let sessionIdentifier = "com.example.gemma_local_app.model_download.background"

  private var eventSink: FlutterEventSink?
  private var backgroundCompletionHandler: (() -> Void)?
  private var current: DownloadRequest?
  private var currentTask: URLSessionDownloadTask?
  private var resumeOffsets: [Int: Int64] = [:]
  private var expectsPartialResponse: [Int: Bool] = [:]
  private var lastProgressTs = Date().timeIntervalSince1970
  private var lastProgressBytes: Int64 = 0

  private lazy var session: URLSession = {
    let config = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
    config.sessionSendsLaunchEvents = true
    config.isDiscretionary = false
    config.allowsCellularAccess = true
    config.allowsExpensiveNetworkAccess = true
    config.allowsConstrainedNetworkAccess = true
    config.httpAdditionalHeaders = ["Accept-Encoding": "identity"]
    return URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }()

  func register(with messenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      let args = call.arguments as? [String: Any] ?? [:]
      do {
        switch call.method {
        case "refreshStatus":
          result(try self.refreshStatus(args: args))
        case "download":
          try self.download(args: args)
          result(nil)
        case "cancel":
          self.cancel()
          result(nil)
        case "delete":
          result(try self.delete(args: args))
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "IOS_DOWNLOAD_ERROR", message: error.localizedDescription, details: nil))
      }
    }

    let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
    eventChannel.setStreamHandler(IOSDownloadStreamHandler(manager: self))
  }

  func handleEventsForBackgroundURLSession(_ identifier: String, completionHandler: @escaping () -> Void) {
    if identifier == sessionIdentifier {
      backgroundCompletionHandler = completionHandler
      _ = session
    } else {
      completionHandler()
    }
  }

  func setEventSink(_ sink: FlutterEventSink?) {
    eventSink = sink
  }

  private func refreshStatus(args: [String: Any]) throws -> [String: Any] {
    let request = try DownloadRequest(args: args)
    let finalFile = request.finalFile
    let tmpFile = request.tmpFile
    if FileManager.default.fileExists(atPath: finalFile.path) {
      let size = fileSize(finalFile)
      if request.totalBytes <= 0 || size >= request.totalBytes {
        return statusMap(status: "succeeded", receivedBytes: size, totalBytes: request.totalBytes, localPath: finalFile.path)
      }
    }
    if FileManager.default.fileExists(atPath: tmpFile.path) {
      return statusMap(status: "partiallyDownloaded", receivedBytes: fileSize(tmpFile), totalBytes: request.totalBytes, localPath: finalFile.path)
    }
    return statusMap(status: "notDownloaded", totalBytes: request.totalBytes, localPath: finalFile.path)
  }

  private func download(args: [String: Any]) throws {
    let request = try DownloadRequest(args: args)
    current = request
    try FileManager.default.createDirectory(at: request.directory, withIntermediateDirectories: true)

    if FileManager.default.fileExists(atPath: request.finalFile.path) {
      let size = fileSize(request.finalFile)
      if request.totalBytes <= 0 || size >= request.totalBytes {
        emit(statusMap(status: "succeeded", receivedBytes: size, totalBytes: request.totalBytes, localPath: request.finalFile.path))
        return
      }
    }

    cancel()
    let downloadedBytes = fileSize(request.tmpFile)
    lastProgressTs = Date().timeIntervalSince1970
    lastProgressBytes = downloadedBytes

    var urlRequest = URLRequest(url: request.url)
    urlRequest.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
    let expectsPartial = downloadedBytes > 0
    if expectsPartial {
      urlRequest.setValue("bytes=\(downloadedBytes)-", forHTTPHeaderField: "Range")
      emit(statusMap(status: "inProgress", receivedBytes: downloadedBytes, totalBytes: request.totalBytes, localPath: request.finalFile.path))
    }
    let task = session.downloadTask(with: urlRequest)
    task.taskDescription = request.encodedDescription
    resumeOffsets[task.taskIdentifier] = downloadedBytes
    expectsPartialResponse[task.taskIdentifier] = expectsPartial
    currentTask = task
    task.resume()
  }

  private func cancel() {
    currentTask?.cancel()
    currentTask = nil
  }

  private func delete(args: [String: Any]) throws -> [String: Any] {
    cancel()
    let request = try DownloadRequest(args: args)
    try? FileManager.default.removeItem(at: request.finalFile)
    try? FileManager.default.removeItem(at: request.tmpFile)
    return try refreshStatus(args: args)
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard let request = request(for: downloadTask) else { return }
    do {
      try FileManager.default.createDirectory(at: request.directory, withIntermediateDirectories: true)
      let responseCode = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
      let expectedPartial = expectsPartialResponse[downloadTask.taskIdentifier] ?? false

      if expectedPartial && responseCode == 206 {
        try appendFile(from: location, to: request.tmpFile)
      } else {
        if expectedPartial && responseCode != 200 && responseCode != 0 {
          throw NSError(
            domain: "IOSModelDownload",
            code: responseCode,
            userInfo: [NSLocalizedDescriptionKey: "HTTP Range resume failed: \(responseCode)"]
          )
        }
        if FileManager.default.fileExists(atPath: request.tmpFile.path) {
          try FileManager.default.removeItem(at: request.tmpFile)
        }
        try FileManager.default.moveItem(at: location, to: request.tmpFile)
      }

      let tmpSize = fileSize(request.tmpFile)
      if request.totalBytes > 0 && tmpSize < request.totalBytes {
        emit(statusMap(status: "partiallyDownloaded", receivedBytes: tmpSize, totalBytes: request.totalBytes, localPath: request.finalFile.path))
        return
      }
      if FileManager.default.fileExists(atPath: request.finalFile.path) {
        try FileManager.default.removeItem(at: request.finalFile)
      }
      try FileManager.default.moveItem(at: request.tmpFile, to: request.finalFile)
      let size = fileSize(request.finalFile)
      emit(statusMap(status: "succeeded", receivedBytes: size, totalBytes: max(size, request.totalBytes), localPath: request.finalFile.path))
      resumeOffsets.removeValue(forKey: downloadTask.taskIdentifier)
      expectsPartialResponse.removeValue(forKey: downloadTask.taskIdentifier)
    } catch {
      emit(statusMap(status: "failed", receivedBytes: fileSize(request.tmpFile), totalBytes: request.totalBytes, errorMessage: error.localizedDescription, localPath: request.finalFile.path))
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let request = request(for: task) else { return }
    if let error {
      emit(statusMap(status: "failed", receivedBytes: fileSize(request.tmpFile), totalBytes: request.totalBytes, errorMessage: error.localizedDescription, localPath: request.finalFile.path))
    }
    resumeOffsets.removeValue(forKey: task.taskIdentifier)
    expectsPartialResponse.removeValue(forKey: task.taskIdentifier)
    if task.taskIdentifier == currentTask?.taskIdentifier {
      currentTask = nil
    }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard let request = request(for: downloadTask) else { return }
    let offset = resumeOffsets[downloadTask.taskIdentifier] ?? 0
    let received = offset + totalBytesWritten
    let now = Date().timeIntervalSince1970
    let elapsed = max(0.001, now - lastProgressTs)
    let delta = received - lastProgressBytes
    let bps = Int64(Double(delta) / elapsed)
    lastProgressTs = now
    lastProgressBytes = received
    let total = request.totalBytes > 0 ? request.totalBytes : max(received, offset + totalBytesExpectedToWrite)
    emit(statusMap(status: "inProgress", receivedBytes: received, totalBytes: total, bytesPerSecond: bps, localPath: request.finalFile.path))
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    DispatchQueue.main.async { [weak self] in
      self?.backgroundCompletionHandler?()
      self?.backgroundCompletionHandler = nil
    }
  }

  private func request(for task: URLSessionTask) -> DownloadRequest? {
    if let desc = task.taskDescription, let decoded = DownloadRequest(encodedDescription: desc) {
      return decoded
    }
    return current
  }

  private func emit(_ map: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(map)
    }
  }

  private func statusMap(
    status: String,
    receivedBytes: Int64 = 0,
    totalBytes: Int64 = 0,
    bytesPerSecond: Int64 = 0,
    errorMessage: String = "",
    localPath: String = ""
  ) -> [String: Any] {
    [
      "status": status,
      "receivedBytes": receivedBytes,
      "totalBytes": totalBytes,
      "bytesPerSecond": bytesPerSecond,
      "errorMessage": errorMessage,
      "localPath": localPath,
    ]
  }

  private func appendFile(from source: URL, to destination: URL) throws {
    if !FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.moveItem(at: source, to: destination)
      return
    }
    let input = try FileHandle(forReadingFrom: source)
    defer { try? input.close() }
    let output = try FileHandle(forWritingTo: destination)
    defer { try? output.close() }
    output.seekToEndOfFile()
    while autoreleasepool(invoking: {
      let data = input.readData(ofLength: 1024 * 1024)
      if data.isEmpty { return false }
      output.write(data)
      return true
    }) {}
    try? FileManager.default.removeItem(at: source)
  }

  private func fileSize(_ url: URL) -> Int64 {
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    return attrs?[.size] as? Int64 ?? 0
  }
}

private final class IOSDownloadStreamHandler: NSObject, FlutterStreamHandler {
  private weak var manager: IOSModelDownloadManager?

  init(manager: IOSModelDownloadManager) {
    self.manager = manager
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    manager?.setEventSink(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    manager?.setEventSink(nil)
    return nil
  }
}

private struct DownloadRequest: Codable {
  let name: String
  let urlString: String
  let normalizedName: String
  let version: String
  let fileName: String
  let totalBytes: Int64

  init(args: [String: Any]) throws {
    name = args["name"] as? String ?? "Gemma-4-E2B-it"
    urlString = args["url"] as? String ?? ""
    normalizedName = args["normalizedName"] as? String ?? "Gemma_4_E2B_it"
    version = args["version"] as? String ?? ""
    fileName = args["fileName"] as? String ?? "gemma-4-E2B-it.litertlm"
    if let n = args["totalBytes"] as? NSNumber {
      totalBytes = n.int64Value
    } else if let i = args["totalBytes"] as? Int64 {
      totalBytes = i
    } else if let i = args["totalBytes"] as? Int {
      totalBytes = Int64(i)
    } else {
      totalBytes = 0
    }
    if URL(string: urlString) == nil {
      throw NSError(domain: "IOSModelDownload", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid model URL"])
    }
  }

  init?(encodedDescription: String) {
    guard let data = encodedDescription.data(using: .utf8),
      let value = try? JSONDecoder().decode(DownloadRequest.self, from: data) else {
      return nil
    }
    self = value
  }

  var url: URL { URL(string: urlString)! }

  var directory: URL {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return root.appendingPathComponent(normalizedName).appendingPathComponent(version)
  }

  var finalFile: URL { directory.appendingPathComponent(fileName) }

  var tmpFile: URL { directory.appendingPathComponent("\(fileName).gallerytmp") }

  var encodedDescription: String {
    let data = try? JSONEncoder().encode(self)
    return String(data: data ?? Data(), encoding: .utf8) ?? ""
  }
}
