import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Explicitly start APNs registration. Firebase Messaging's iOS plugin
    // receives the resulting device-token callback through FlutterAppDelegate.
    let didFinishLaunching = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
    application.registerForRemoteNotifications()
    return didFinishLaunching
  }
}
