import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var reminderLinkPending = false
  private var reminderChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    if var support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      do {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try support.setResourceValues(values)
      } catch {
        // No user data has been opened yet; do not silently enable system backup.
        fatalError("Unable to exclude private storage from system backup")
      }
    }

    if let url = launchOptions?[.url] as? URL, url.scheme == "anban" {
      reminderLinkPending = true
    }

    let controller = window?.rootViewController as? FlutterViewController
    if let messenger = controller?.binaryMessenger {
      setupReminderChannel(messenger: messenger)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme == "anban" {
      reminderLinkPending = true
      reminderChannel?.invokeMethod("reminderLink", arguments: nil)
      return true
    }
    return super.application(app, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    setupReminderChannel(
      messenger: engineBridge.pluginRegistry.registrar(
        forPlugin: "app.anban.anban/reminders"
      ).messenger()
    )
  }

  private func setupReminderChannel(messenger: FlutterBinaryMessenger) {
    if reminderChannel != nil {
      return
    }
    let channel = FlutterMethodChannel(
      name: "app.anban.anban/reminders",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      switch call.method {
      case "consumeReminderLink":
        result(self.reminderLinkPending)
        self.reminderLinkPending = false
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.reminderChannel = channel
  }
}
