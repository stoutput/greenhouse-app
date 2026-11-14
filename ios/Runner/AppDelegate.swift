import Flutter
import UIKit
import LocalAuthentication

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "app.greenhouse/biometric_enrollment",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "reset" || call.method == "hasChanged" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let context = LAContext()
      var error: NSError?
      let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
      let domain: Data?
      if #available(iOS 18.0, *) {
        domain = context.domainState.biometry.stateHash
      } else {
        domain = context.evaluatedPolicyDomainState
      }
      let state: String
      if available, let domain = domain {
        state = domain.base64EncodedString()
      } else if let code = error?.code,
                code == LAError.biometryNotEnrolled.rawValue || code == LAError.biometryNotAvailable.rawValue {
        state = "none"
      } else {
        result(FlutterError(code: "enrollment_unavailable", message: "Could not check biometric enrollment", details: nil))
        return
      }
      let key = "greenhouse.biometric_enrollment"
      if call.method == "reset" {
        UserDefaults.standard.set(state, forKey: key)
        result(nil)
      } else {
        result(UserDefaults.standard.string(forKey: key) != state)
      }
    }
  }
}
