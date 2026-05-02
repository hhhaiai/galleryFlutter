import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    guard let controller = window?.rootViewController as? FlutterViewController,
      let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
      return
    }
    appDelegate.registerFlutterChannels(with: controller.binaryMessenger)
  }
}
