import Flutter
import Contacts
import Foundation
import UIKit

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
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AzooKeyPlatform") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "net.azookey/platform",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handlePlatformCall(call, result: result)
    }
  }

  private func handlePlatformCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let defaults = UserDefaults(suiteName: "group.com.azooKey.keyboard")!
    switch call.method {
    case "loadState":
      result(defaults.string(forKey: "azookey_flutter_state"))
    case "saveState":
      guard let arguments = call.arguments as? [String: Any],
            let state = arguments["state"] as? String else {
        result(FlutterError(code: "invalid_state", message: "state must be a JSON string", details: nil))
        return
      }
      defaults.set(state, forKey: "azookey_flutter_state")
      result(nil)
    case "keyboardStatus":
      let identifiers = UITextInputMode.activeInputModes.compactMap {
        $0.value(forKey: "identifier") as? String
      }
      let enabled = identifiers.contains { $0.hasPrefix("io.github.StupidGame.azookeyFlutter.AzooKeyKeyboard") }
      result(["enabled": enabled, "fullAccess": enabled, "platform": "ios"])
    case "openKeyboardSettings":
      guard let url = URL(string: UIApplication.openSettingsURLString) else {
        result(nil)
        return
      }
      UIApplication.shared.open(url) { _ in result(nil) }
    case "configureDictionarySubmission":
      let arguments = call.arguments as? [String: Any]
      let endpoint = (arguments?["endpoint"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if let url = URL(string: endpoint), url.scheme == "https", url.host != nil {
        defaults.set(endpoint, forKey: "keynako_dictionary_submission_url")
      } else {
        defaults.removeObject(forKey: "keynako_dictionary_submission_url")
      }
      result(nil)
    case "shareText":
      let arguments = call.arguments as? [String: Any]
      let subject = arguments?["subject"] as? String ?? "Keynako"
      let text = arguments?["text"] as? String ?? ""
      presentShareSheet(items: [subject, text])
      result(nil)
    case "importContacts":
      importContacts(result: result)
    case "saveKeyboardBackgroundImage":
      let arguments = call.arguments as? [String: Any]
      guard let themeId = arguments?["themeId"] as? String,
            !themeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let typedData = arguments?["bytes"] as? FlutterStandardTypedData,
            !typedData.data.isEmpty else {
        result(FlutterError(code: "invalid_image", message: "themeId and image bytes are required", details: nil))
        return
      }
      guard typedData.data.count <= 8 * 1024 * 1024 else {
        result(FlutterError(code: "image_too_large", message: "background image exceeds 8 MB", details: nil))
        return
      }
      do {
        result(try saveKeyboardBackgroundImage(themeId: themeId, data: typedData.data))
      } catch {
        result(FlutterError(code: "image_save_failed", message: error.localizedDescription, details: nil))
      }
    case "deleteKeyboardBackgroundImage":
      let arguments = call.arguments as? [String: Any]
      if let path = arguments?["path"] as? String {
        try? deleteKeyboardBackgroundImage(path: path)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func presentShareSheet(items: [Any]) {
    let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
          let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
      return
    }
    if let popover = activity.popoverPresentationController {
      popover.sourceView = root.view
      popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 1, height: 1)
    }
    root.present(activity, animated: true)
  }

  private func saveKeyboardBackgroundImage(themeId: String, data: Data) throws -> String {
    let directory = try backgroundImageDirectory()
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    let safeId = String(themeId.unicodeScalars.map { scalar in
      allowed.contains(scalar) ? Character(String(scalar)) : "_"
    }.prefix(80))
    let target = directory.appendingPathComponent("\(safeId.isEmpty ? "theme" : safeId).image")
    guard let source = UIImage(data: data), source.size.width > 0, source.size.height > 0 else {
      throw CocoaError(.fileReadCorruptFile)
    }
    // Keep the source aspect ratio. The keyboard extension crops it against its
    // actual bounds, including the user's current height scale.
    try data.write(to: target, options: .atomic)
    return target.path
  }

  private func deleteKeyboardBackgroundImage(path: String) throws {
    let directory = try backgroundImageDirectory().resolvingSymlinksInPath()
    let target = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    guard target.deletingLastPathComponent() == directory else { return }
    try? FileManager.default.removeItem(at: target)
  }

  private func backgroundImageDirectory() throws -> URL {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group.com.azooKey.keyboard"
    ) else {
      throw CocoaError(.fileNoSuchFile)
    }
    let directory = container.appendingPathComponent("ThemeBackgrounds", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }

  private func importContacts(result: @escaping FlutterResult) {
    let store = CNContactStore()
    store.requestAccess(for: .contacts) { granted, authorizationError in
      guard granted else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "permission_denied",
            message: authorizationError?.localizedDescription ?? "Contacts permission was denied",
            details: nil
          ))
        }
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
        let keys: [CNKeyDescriptor] = [
          CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
          CNContactPhoneticGivenNameKey as CNKeyDescriptor,
          CNContactPhoneticFamilyNameKey as CNKeyDescriptor,
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        var contacts: [[String: String]] = []
        try store.enumerateContacts(with: request) { contact, _ in
          let word = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
          guard !word.isEmpty else { return }
          let ruby = (contact.phoneticFamilyName + contact.phoneticGivenName)
          contacts.append(["word": word, "ruby": ruby.isEmpty ? word : ruby])
        }
          DispatchQueue.main.async { result(contacts) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "contacts_error", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

}
