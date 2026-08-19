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
    // This endpoint and both form entry IDs intentionally match the Swift azooKey app.
    private static let suggestionEndpoint = URL(
        string: "https://docs.google.com/forms/d/e/1FAIpQLSeTdOtFZfuFHurrDMIIzLyX-Z84Y3IKHflewNZ8dPOFgCTOtw/formResponse"
    )!
    private static let legacyWrongConversionEndpoint = URL(
        string: "https://docs.google.com/forms/d/e/1FAIpQLSfpYQqbX8u5SgGVfXjNzCPtKAH_5Mp7PCkUiCiUceEaevb8pQ/formResponse"
    )!

    static func submit(
        report: WrongConversionReport,
        settings: [String: Any],
        appVersion: String,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        let input: [String: Any] = [
            "text": report.reading,
            "segments": [["value": report.rawInput, "inputStyle": report.inputStyle]],
        ]
        var payload: [String: Any] = [
            "suggested": report.suggested,
            "selected": report.selected,
            "selectedIndex": String(report.selectedIndex),
            "input": input,
            "appVersion": appVersion,
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "zenzaiEnabled": String(settings["enable_zenzai"] as? Bool ?? false),
            "zenzaiEffort": effortName(settings["zenzai_effort"] as? Int ?? 1),
            "japaneseLayout": report.japaneseLayout,
            "textContentType": report.textContentType,
            "returnKeyType": report.returnKeyType,
            "date": ISO8601DateFormatter().string(from: Date()),
        ]
        if settings["wrong_conversion_include_context"] as? Bool == true {
            if !report.leftContext.isEmpty {
                payload["leftSideContext"] = String(report.leftContext.suffix(10))
            }
            if !report.rightContext.isEmpty {
                payload["rightSideContext"] = String(report.rightContext.prefix(10))
            }
        }
        if let nickname = settings["wrong_conversion_report_user_nickname"] as? String,
           !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["userNickname"] = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let payloadString = String(data: payloadData, encoding: .utf8) else {
            completion(false)
            return
        }
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "entry.1715004013", value: "non_first_candidate_selection_report"),
            URLQueryItem(name: "entry.562739847", value: payloadString),
        ]
        var request = URLRequest(url: suggestionEndpoint)
        request.httpMethod = "POST"
        request.setValue("no-cors", forHTTPHeaderField: "mode")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        URLSession.shared.dataTask(with: request) { _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            completion(error == nil && (200..<400).contains(status))
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

    private static func effortName(_ value: Int) -> String {
        switch value {
        case 0: "low"
        case 2: "high"
        default: "medium"
        }
    }
}
