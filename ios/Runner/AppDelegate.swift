import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let modelDownloadManager = IOSModelDownloadManager()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      modelDownloadManager.register(with: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
