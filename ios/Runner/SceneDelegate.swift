import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var privacyCover: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    let enabled = UserDefaults.standard.object(forKey: "flutter.greenhouse.lock_enabled") as? Bool ?? true
    guard enabled, let window = (scene as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow }) else { return }
    let cover = UIView(frame: window.bounds)
    cover.backgroundColor = .systemBackground
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(cover)
    privacyCover = cover
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}
