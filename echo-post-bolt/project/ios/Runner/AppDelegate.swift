import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // Register the native video player plugin
    let controller = window?.rootViewController as! FlutterViewController
    let registrar = self.registrar(forPlugin: "NativeVideoPlayerPlugin")!
    NativeVideoPlayerPlugin.register(with: registrar)
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
} 