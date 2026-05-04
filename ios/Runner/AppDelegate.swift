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
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      registerFlutterChannels(with: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
