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
    case "shareText":
      let arguments = call.arguments as? [String: Any]
      let subject = arguments?["subject"] as? String ?? "Keynako"
      let text = arguments?["text"] as? String ?? ""
      presentShareSheet(items: [subject, text])
      result(nil)
    case "importContacts":
      importContacts(result: result)
    case "submitSharedWord":
      let arguments = call.arguments as? [String: Any]
      let word = arguments?["word"] as? String ?? ""
      guard !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        result(FlutterError(code: "invalid_word", message: "word must not be empty", details: nil))
        return
      }
      submitSharedWord(
        word: word,
        ruby: arguments?["ruby"] as? String ?? "",
        note: arguments?["note"] as? String,
        categories: arguments?["categories"] as? [String] ?? []
      ) { success in
        DispatchQueue.main.async { result(success) }
      }
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

  private func submitSharedWord(
    word: String,
    ruby: String,
    note: String?,
    categories: [String],
    completion: @escaping (Bool) -> Void
  ) {
    let endpoint = URL(
      string: "https://docs.google.com/forms/d/e/1FAIpQLSceGtIHH8P-KbrB2ownprap3cUVVJegbhGekfz1xCiwPxBNfg/formResponse"
    )!
    let noteText = (note ?? "備考記入なし")
      + "\nアプリ内フォームから送信\nKeynako 3.0.1"
    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "entry.1129894332", value: "3"),
      URLQueryItem(name: "entry.813756984", value: word),
      URLQueryItem(name: "entry.688013311", value: ruby.isEmpty ? "読み記入なし" : ruby),
      URLQueryItem(name: "entry.1136445695", value: noteText),
      URLQueryItem(name: "entry.2110887544", value: "__other_option__"),
      URLQueryItem(
        name: "entry.2110887544.other_option_response",
        value: categories.isEmpty ? "品詞記入無し" : categories.joined(separator: "、")
      ),
    ]
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("no-cors", forHTTPHeaderField: "mode")
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
    URLSession.shared.dataTask(with: request) { _, response, error in
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      completion(error == nil && (200..<400).contains(status))
    }.resume()
  }
}
