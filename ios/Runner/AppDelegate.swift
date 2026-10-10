import Flutter
import Photos
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Held while shots are still being processed (BackgroundTime in Dart), so
  /// leaving the app right after a shot doesn't pause it until next launch.
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications: route notification taps / foreground
    // presentation through the plugin.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DarkroomBackgroundTime") else {
      return
    }
    // The phone's charge, for the digital bodies' battery gauges.
    let battery = FlutterMethodChannel(name: "darkroom/battery", binaryMessenger: registrar.messenger())
    battery.setMethodCallHandler { call, result in
      guard call.method == "level" else {
        result(FlutterMethodNotImplemented)
        return
      }
      UIDevice.current.isBatteryMonitoringEnabled = true
      let level = UIDevice.current.batteryLevel
      result(level < 0 ? nil : Int((level * 100).rounded()))
    }
    // What's still in one of our photo albums (deleted copies are offered
    // again). Needs full (or limited) library access, asked for from Dart
    // with an explanation first.
    let gallery = FlutterMethodChannel(name: "darkroom/gallery", binaryMessenger: registrar.messenger())
    gallery.setMethodCallHandler { call, result in
      switch call.method {
      case "access":
        result(Self.accessName(PHPhotoLibrary.authorizationStatus(for: .readWrite)))
      case "request":
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
          DispatchQueue.main.async { result(status == .authorized || status == .limited) }
        }
      case "names":
        let album = (call.arguments as? [String: Any])?["album"] as? String ?? ""
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
          result(nil)
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          let names = Self.albumNames(album)
          DispatchQueue.main.async { result(names) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    let channel = FlutterMethodChannel(name: "darkroom/background", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "begin":
        self?.beginBackgroundTime()
        result(nil)
      case "end":
        self?.endBackgroundTime()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func accessName(_ status: PHAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "full"
    case .limited: return "limited"
    case .notDetermined: return "undetermined"
    default: return "denied"
    }
  }

  /// The original file names of the assets in the album(s) titled [album].
  private static func albumNames(_ album: String) -> [String] {
    var names: [String] = []
    let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
    collections.enumerateObjects { collection, _, _ in
      guard collection.localizedTitle == album else { return }
      PHAsset.fetchAssets(in: collection, options: nil).enumerateObjects { asset, _, _ in
        for resource in PHAssetResource.assetResources(for: asset) {
          names.append(resource.originalFilename)
        }
      }
    }
    return names
  }

  private func beginBackgroundTime() {
    guard backgroundTask == .invalid else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Darkroom processing") { [weak self] in
      // Out of time: the rest resumes on the next launch (CaptureProcessor.recover).
      self?.endBackgroundTime()
    }
  }

  private func endBackgroundTime() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }
}
