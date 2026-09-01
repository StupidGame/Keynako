import Foundation

struct WrongConversionReport {
    let suggested: String
    let selected: String
    let selectedIndex: Int
    let reading: String
    let rawInput: String
    let inputStyle: String
    let leftContext: String
    let rightContext: String
    let japaneseLayout: String
    let textContentType: String
    let returnKeyType: String
}

enum ReportClient {
    private static let legacyWrongConversionEndpoint = URL(
        string: "https://docs.google.com/forms/d/e/1FAIpQLSfpYQqbX8u5SgGVfXjNzCPtKAH_5Mp7PCkUiCiUceEaevb8pQ/formResponse"
    )!

    static func submitSharedConversionImprovement(
        endpoint: String,
        report: WrongConversionReport,
        appVersion: String,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedEndpoint),
              url.scheme == "https",
              url.host != nil else {
            completion(false)
            return
        }
        let payload: [String: Any] = [
            "word": report.selected.trimmingCharacters(in: .whitespacesAndNewlines),
            "ruby": report.reading.trimmingCharacters(in: .whitespacesAndNewlines),
            "importance": 3,
            "categories": [String](),
            "note": "IME候補改善: 第\(report.selectedIndex + 1)候補を選択",
            "source": "Keynako IME",
            "app_version": appVersion,
        ]
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Keynako \(appVersion)", forHTTPHeaderField: "User-Agent")
        request.httpBody = payloadData
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            completion(
                error == nil &&
                    (200..<300).contains(status) &&
                    responseAcceptsSubmission(data)
            )
        }.resume()
    }

    static func submitLegacyWrongConversion(
        candidate: String,
        ruby: String,
        index: Int,
        appVersion: String,
        learningEnabled: Bool,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "entry.134904003", value: candidate),
            URLQueryItem(name: "entry.869464972", value: ruby),
            URLQueryItem(name: "entry.1459534202", value: String(index)),
            URLQueryItem(name: "entry.571429448", value: appVersion),
            URLQueryItem(name: "entry.524189292", value: learningEnabled ? "有効" : "無効"),
        ]
        var request = URLRequest(url: legacyWrongConversionEndpoint)
        request.httpMethod = "POST"
        request.setValue("no-cors", forHTTPHeaderField: "mode")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        URLSession.shared.dataTask(with: request) { _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            completion(error == nil && (200..<400).contains(status))
        }.resume()
    }

    private static func responseAcceptsSubmission(_ data: Data?) -> Bool {
        guard let data, !data.isEmpty else { return true }
        guard data.count <= 64 * 1024,
              let decoded = try? JSONSerialization.jsonObject(with: data) else { return false }
        guard let response = decoded as? [String: Any] else { return true }
        return response["ok"] as? Bool != false
    }
}
