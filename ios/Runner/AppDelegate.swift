import AVFoundation
import AVKit
import Flutter
import Photos
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Held while shots are still being processed (BackgroundTime in Dart), so
  /// leaving the app right after a shot doesn't pause it until next launch.
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  /// darkroom/volume: while the camera is on screen the volume buttons (and
  /// the iPhone 16's Camera Control press) are the shutter, as on Android.
  private var volumeChannel: FlutterMethodChannel?
  private var captureInteraction: AnyObject?

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
    // The phone's total RAM, so the app can size its work to it.
    let device = FlutterMethodChannel(name: "darkroom/device", binaryMessenger: registrar.messenger())
    device.setMethodCallHandler { call, result in
      guard call.method == "memory" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(["total": Int64(ProcessInfo.processInfo.physicalMemory), "lowRam": false])
    }
    // Camera / microphone: granted?, ask (only while iOS still will), and
    // the app's page in Settings for when it won't.
    let permissions = FlutterMethodChannel(name: "darkroom/permissions", binaryMessenger: registrar.messenger())
    permissions.setMethodCallHandler { call, result in
      let kind = (call.arguments as? [String: Any])?["kind"] as? String
      let media: AVMediaType? = kind == "camera" ? .video : (kind == "microphone" ? .audio : nil)
      switch call.method {
      case "granted":
        result(media.map { AVCaptureDevice.authorizationStatus(for: $0) == .authorized } ?? false)
      case "request":
        guard let media = media else {
          result(false)
          return
        }
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: result(true)
        case .notDetermined:
          AVCaptureDevice.requestAccess(for: media) { ok in DispatchQueue.main.async { result(ok) } }
        default: result(false)
        }
      case "openSettings":
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
          result(true)
        } else {
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
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
      case "entries":
        let album = (call.arguments as? [String: Any])?["album"] as? String ?? ""
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
          result(nil)
          return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          let entries = Self.albumEntries(album)
          DispatchQueue.main.async { result(entries) }
        }
      case "rename":
        // Photos keeps an asset's original file name: nothing to rename.
        result(false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    // Volume buttons / Camera Control as the shutter (iOS 17.2+: Apple's
    // capture-event API; it only takes them while the app's camera runs, and
    // the volume changes as usual otherwise).
    let volume = FlutterMethodChannel(name: "darkroom/volume", binaryMessenger: registrar.messenger())
    volumeChannel = volume
    volume.setMethodCallHandler { [weak self] call, result in
      guard call.method == "capture" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.captureButtons(call.arguments as? Bool == true)
      result(nil)
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

  /// The assets in the album(s) titled [album]: local identifier (stable)
  /// and original file name.
  private static func albumEntries(_ album: String) -> [[String: String]] {
    var out: [[String: String]] = []
    let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
    collections.enumerateObjects { collection, _, _ in
      guard collection.localizedTitle == album else { return }
      PHAsset.fetchAssets(in: collection, options: nil).enumerateObjects { asset, _, _ in
        let name = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
        out.append(["id": asset.localIdentifier, "name": name])
      }
    }
    return out
  }

  /// Volume down and the Camera Control press come in as the primary
  /// capture event, volume up as the secondary: Dart's VolumeKeys gets
  /// (up?, pressed / released) like Android's keys.
  private func captureButtons(_ on: Bool) {
    guard #available(iOS 17.2, *) else { return }
    if let interaction = captureInteraction as? AVCaptureEventInteraction {
      interaction.isEnabled = on
      return
    }
    guard on, let view = Self.rootView() else { return }
    let send: (Bool, AVCaptureEvent) -> Void = { [weak self] up, event in
      let down: Bool
      switch event.phase {
      case .began: down = true
      case .ended, .cancelled: down = false
      @unknown default: return
      }
      self?.volumeChannel?.invokeMethod("key", arguments: ["up": up, "down": down])
    }
    let interaction = AVCaptureEventInteraction(
      primary: { event in send(false, event) },
      secondary: { event in send(true, event) }
    )
    view.addInteraction(interaction)
    captureInteraction = interaction
  }

  private static func rootView() -> UIView? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
    return window?.rootViewController?.view
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
