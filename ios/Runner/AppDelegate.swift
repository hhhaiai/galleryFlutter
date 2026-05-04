import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let modelDownloadManager = IOSModelDownloadManager()
  private let gemmaRuntime = IOSGemmaRuntime()
  private let audioInput = IOSAudioInput()
  private var didRegisterFlutterChannels = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Do NOT call super.application(...). FlutterAppDelegate's super calls
    // GeneratedPluginRegistrant which registers background_downloader, and
    // BackgroundDownloaderPlugin.register(with:) crashes with
    // swift_getObjectType SIGSEGV on this iOS 18 device.
    // SafePluginRegistrant registers the plugins we actually need.
    SafePluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      registerFlutterChannels(with: controller.binaryMessenger)
    }
    return true
  }

  func registerFlutterChannels(with messenger: FlutterBinaryMessenger) {
    guard !didRegisterFlutterChannels else { return }
    didRegisterFlutterChannels = true
    modelDownloadManager.register(with: messenger)
    gemmaRuntime.register(with: messenger)
    audioInput.register(with: messenger)
  }

  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    modelDownloadManager.handleEventsForBackgroundURLSession(
      identifier,
      completionHandler: completionHandler
    )
  }
}
