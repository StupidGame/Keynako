import UIKit
import AzooKeyConverterBridge

final class KeyboardViewController: UIInputViewController {
    private let rootStack = UIStackView()
    private let candidateScroll = UIScrollView()
    private let candidateStack = UIStackView()
    private let keyboardStack = UIStackView()
    private var heightConstraint: NSLayoutConstraint?

    private var state: [String: Any] = [:]
    private var settings: [String: Any] = [:]
    private var palette = KeyboardPalette.light
    private var composing = ""
    private var rawRoman = ""
    private var lastDisplayed = ""
    private var candidates: [String] = []
    private var mode = "japanese"
    private var layout = "flick"
    private var shift = false
    private var capsLock = false
    private var activeCustomTab: String?
    private var pendingReport: WrongConversionReport?
    private var osLexicon: [String: [String]] = [:]
    private lazy var conversionEngine: AzooKeyConversionEngine? = {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.azooKey.keyboard"
        ) else { return nil }
        return AzooKeyConversionEngine(sharedContainerURL: container)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        reloadState()
        loadOSLexiconIfNeeded()
        renderCandidates()
        renderKeyboard()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadState()
        loadOSLexiconIfNeeded()
        resetComposition()
        mode = "japanese"
        layout = stringSetting("keyboard_type", fallback: "flick")
        renderCandidates()
        renderKeyboard()
    }

    override func textWillChange(_ textInput: (any UITextInput)?) {
        super.textWillChange(textInput)
        reloadState()
    }

    private func configureView() {
        rootStack.axis = .vertical
        rootStack.spacing = 0
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        candidateStack.axis = .horizontal
        candidateStack.alignment = .fill
        candidateStack.spacing = 1
        candidateStack.translatesAutoresizingMaskIntoConstraints = false
        candidateScroll.showsHorizontalScrollIndicator = false
        candidateScroll.addSubview(candidateStack)
        NSLayoutConstraint.activate([
            candidateStack.leadingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.leadingAnchor),
            candidateStack.trailingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.trailingAnchor),
            candidateStack.topAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.topAnchor),
            candidateStack.bottomAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.bottomAnchor),
            candidateStack.heightAnchor.constraint(equalTo: candidateScroll.frameLayoutGuide.heightAnchor),
            candidateScroll.heightAnchor.constraint(equalToConstant: 42),
        ])
        rootStack.addArrangedSubview(candidateScroll)

        keyboardStack.axis = .vertical
        keyboardStack.distribution = .fillEqually
        keyboardStack.spacing = 4
        keyboardStack.layoutMargins = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        keyboardStack.isLayoutMarginsRelativeArrangement = true
        rootStack.addArrangedSubview(keyboardStack)
        heightConstraint = view.heightAnchor.constraint(equalToConstant: 258)
        heightConstraint?.priority = .defaultHigh
        heightConstraint?.isActive = true
    }

    private func reloadState() {
        let defaults = UserDefaults(suiteName: "group.com.azooKey.keyboard")!
        guard let value = defaults.string(forKey: "azookey_flutter_state"),
              let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            state = [:]
            settings = [:]
            palette = traitCollection.userInterfaceStyle == .dark ? .dark : .light
            return
        }
        state = object
        settings = object["settings"] as? [String: Any] ?? [:]
        if settings["memory_reset_setting"] != nil,
           settings["memory_reset_setting"] as? Bool != false {
            conversionEngine?.resetLearning()
            settings["memory_reset_setting"] = false
            state["settings"] = settings
            saveState()
        }
        palette = loadPalette()
        view.backgroundColor = palette.background
        keyboardStack.backgroundColor = palette.background
        let scale = doubleSetting("keyboard_height_scale", fallback: 1).clamped(to: 0.7 ... 1.4)
        heightConstraint?.constant = 42 + 216 * scale
    }

    private func loadPalette() -> KeyboardPalette {
        let dark = traitCollection.userInterfaceStyle == .dark
        let selectedKey = dark ? "darkThemeId" : "lightThemeId"
        let selected = state[selectedKey] as? String ?? (dark ? "midnight" : "classic")
        guard let themes = state["themes"] as? [[String: Any]],
              let theme = themes.first(where: { $0["id"] as? String == selected }) else {
            return dark ? .dark : .light
        }
        return KeyboardPalette(
            background: color(theme["backgroundColor"], fallback: dark ? 0xff111827 : 0xffd1d5db),
            key: color(theme["keyColor"], fallback: dark ? 0xff374151 : 0xffffffff),
            special: color(theme["specialKeyColor"], fallback: dark ? 0xff1f2937 : 0xffadb5bd),
            text: color(theme["textColor"], fallback: dark ? 0xfff9fafb : 0xff111827),
            accent: color(theme["accentColor"], fallback: dark ? 0xff60a5fa : 0xff2563eb)
        )
    }

    private func renderKeyboard() {
        keyboardStack.removeAllArrangedSubviews()
        if let activeCustomTab {
            renderCustomTab(activeCustomTab)
        } else if mode == "symbols" {
            renderSymbols()
        } else if layout == "qwerty" {
            renderQwerty()
        } else {
            renderFlick()
        }
        if activeCustomTab == nil { renderStandaloneCustomKeys() }
    }

    private func renderFlick() {
        let rows: [[FlickDefinition]]
        if mode == "english" {
            rows = [
                [.init(".@", [".", "@", "_", "-", "/"]), .init("ABC", ["a", "b", "c", "A", "B"]), .init("DEF", ["d", "e", "f", "D", "E"]), .action("⌫", "delete")],
                [.init("GHI", ["g", "h", "i", "G", "H"]), .init("JKL", ["j", "k", "l", "J", "K"]), .init("MNO", ["m", "n", "o", "M", "N"]), .action("space", "space")],
                [.init("PQRS", ["p", "q", "r", "s", "P"]), .init("TUV", ["t", "u", "v", "T", "U"]), .init("WXYZ", ["w", "x", "y", "z", "W"]), .action("return", "enter")],
                [.action("☆123", "symbols"), .action("あいう", "japanese"), .init("'\"", ["'", "\"", ":", ";", "!"]), .action("🌐", "nextKeyboard")],
            ]
        } else {
            rows = [
                [.init("あ", ["あ", "い", "う", "え", "お"]), .init("か", ["か", "き", "く", "け", "こ"]), .init("さ", ["さ", "し", "す", "せ", "そ"]), .action("⌫", "delete")],
                [.init("た", ["た", "ち", "つ", "て", "と"]), .init("な", ["な", "に", "ぬ", "ね", "の"]), .init("は", ["は", "ひ", "ふ", "へ", "ほ"]), .action("空白", "space")],
                [.init("ま", ["ま", "み", "む", "め", "も"]), .init("や", ["や", "「", "ゆ", "」", "よ"]), .init("ら", ["ら", "り", "る", "れ", "ろ"]), .action("改行", "enter")],
                [.action("☆123", "symbols"), .action("小ﾞﾟ", "kogana"), .init("わ", ["わ", "を", "ん", "ー", "〜"]), .action("🌐", "nextKeyboard")],
            ]
        }
        for definitions in rows {
            let row = makeRow()
            for definition in definitions {
                let button = FlickButton(definition: definition, sensitivity: CGFloat(doubleSetting("flick_sensitivity_setting", fallback: 1))) { [weak self] value in
                    self?.handleFlickValue(value, definition: definition)
                }
                style(button, special: definition.action != nil)
                row.addArrangedSubview(button)
            }
            keyboardStack.addArrangedSubview(row)
        }
    }

    private func renderQwerty() {
        for (index, letters) in ["qwertyuiop", "asdfghjkl", "zxcvbnm"].enumerated() {
            let row = makeRow()
            if index == 2 {
                row.addArrangedSubview(makeButton(capsLock ? "⇪" : "⇧", special: true, action: toggleShift))
            }
            for character in letters {
                let base = String(character)
                let label = shift || capsLock ? base.uppercased() : base
                row.addArrangedSubview(makeButton(label) { [weak self] in self?.input(label) })
            }
            if index == 2 {
                row.addArrangedSubview(makeButton("⌫", special: true, action: delete))
            }
            keyboardStack.addArrangedSubview(row)
        }
        let bottom = makeRow()
        bottom.addArrangedSubview(makeButton("☆123", special: true) { [weak self] in self?.setMode("symbols") })
        bottom.addArrangedSubview(makeButton("🌐", special: true, action: advanceToNextInputMode))
        let space = makeButton("space", action: self.space)
        bottom.addArrangedSubview(space)
        space.widthAnchor.constraint(equalTo: bottom.widthAnchor, multiplier: 0.42).isActive = true
        bottom.addArrangedSubview(makeButton("return", special: true, action: enter))
        keyboardStack.addArrangedSubview(bottom)
    }

    private func renderSymbols() {
        let rows = [
            ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
            ["-", "/", ":", ";", "(", ")", "¥", "&", "@", "\""],
            ["。", "、", "？", "！", "…", "・", "〜", "#", "%"],
        ]
        for values in rows {
            let row = makeRow()
            for value in values {
                row.addArrangedSubview(makeButton(value) { [weak self] in self?.directCommit(value) })
            }
            keyboardStack.addArrangedSubview(row)
        }
        let bottom = makeRow()
        bottom.addArrangedSubview(makeButton("あいう", special: true) { [weak self] in self?.setMode("japanese") })
        bottom.addArrangedSubview(makeButton("ABC", special: true) { [weak self] in self?.setMode("english") })
        bottom.addArrangedSubview(makeButton("space", action: space))
        bottom.addArrangedSubview(makeButton("⌫", special: true, action: delete))
        bottom.addArrangedSubview(makeButton("return", special: true, action: enter))
        keyboardStack.addArrangedSubview(bottom)
    }

    private func renderCustomTab(_ id: String) {
        guard let tabs = state["customTabs"] as? [[String: Any]],
              let tab = tabs.first(where: { $0["id"] as? String == id }),
              let keys = tab["keys"] as? [[String: Any]] else {
            setMode("japanese")
            return
        }
        let columns = (tab["columns"] as? Int ?? 4).clamped(to: 1 ... 8)
        for start in stride(from: 0, to: keys.count, by: columns) {
            let row = makeRow()
            for key in keys[start ..< min(start + columns, keys.count)] {
                row.addArrangedSubview(makeCustomButton(key))
            }
            keyboardStack.addArrangedSubview(row)
        }
        let bottom = makeRow()
        bottom.addArrangedSubview(makeButton("あいう", special: true) { [weak self] in self?.setMode("japanese") })
        bottom.addArrangedSubview(makeButton("⌫", special: true, action: delete))
        bottom.addArrangedSubview(makeButton("space", action: space))
        bottom.addArrangedSubview(makeButton("return", special: true, action: enter))
        keyboardStack.addArrangedSubview(bottom)
    }

    private func renderStandaloneCustomKeys() {
        let keys = Array((state["customKeys"] as? [[String: Any]] ?? []).prefix(8))
        guard !keys.isEmpty else { return }
        for start in stride(from: 0, to: keys.count, by: 4) {
            let row = makeRow()
            for key in keys[start ..< min(start + 4, keys.count)] {
                row.addArrangedSubview(makeCustomButton(key))
            }
            keyboardStack.addArrangedSubview(row)
        }
    }

    private func makeCustomButton(_ key: [String: Any]) -> UIButton {
        let button = CustomFlickButton(
            key: key,
            sensitivity: CGFloat(doubleSetting("flick_sensitivity_setting", fallback: 1))
        ) { [weak self] action in
            self?.dispatch(action)
            self?.feedback()
        }
        style(button, special: false)
        return button
    }

    private func renderCandidates(showTabs: Bool? = nil) {
        candidateStack.removeAllArrangedSubviews()
        if showTabs ?? composing.isEmpty && rawRoman.isEmpty {
            if boolSetting("display_tab_bar_button", fallback: true) {
                renderTabBar()
            }
            return
        }
        candidates = buildCandidates()
        for (index, candidate) in candidates.enumerated() {
            let button = makeCandidateButton(candidate) { [weak self] in self?.commitCandidate(index) }
            button.longPressAction = { [weak self] in self?.showLegacyReportPrompt(candidate, index: index) }
            button.setTitleColor(index == 0 ? palette.accent : palette.text, for: .normal)
            candidateStack.addArrangedSubview(button)
        }
    }

    private func renderTabBar() {
        let values = state["tabBar"] as? [String] ?? ["dismiss", "resize", "emoji", "japanese", "english"]
        for value in values {
            let title: String
            switch value {
            case "dismiss": title = "⌄"
            case "resize": title = "↔"
            case "emoji": title = "😊"
            case "japanese": title = "あいう"
            case "english": title = "ABC"
            case "clipboard": title = "📋"
            default:
                title = value.hasPrefix("custom:") ? customTabName(String(value.dropFirst(7))) : value
            }
            candidateStack.addArrangedSubview(makeCandidateButton(title) { [weak self] in self?.selectTab(value) })
        }
        if boolSetting("enable_clipboard_history_manager_tab", fallback: false), !values.contains("clipboard") {
            candidateStack.addArrangedSubview(makeCandidateButton("📋", action: showClipboardHistory))
        }
    }

    private func selectTab(_ value: String) {
        switch value {
        case "dismiss": dismissKeyboard()
        case "emoji": showEmoji()
        case "japanese": setMode("japanese")
        case "english": setMode("english")
        case "clipboard": showClipboardHistory()
        default:
            if value.hasPrefix("custom:") {
                activeCustomTab = String(value.dropFirst(7))
                renderKeyboard()
            }
        }
    }

    private func input(_ value: String) {
        if mode == "english" {
            directCommit(value)
            if shift, !capsLock {
                shift = false
                renderKeyboard()
            }
            return
        }
        if layout == "qwerty" {
            rawRoman += value.lowercased()
            composing = romanToHiragana(rawRoman)
        } else {
            composing += value
        }
        updateComposition()
    }

    private func updateComposition() {
        candidates = buildCandidates()
        let displayed = boolSetting("live_conversion", fallback: true) ? (candidates.first ?? composing) : composing
        replaceDisplayed(with: displayed, commit: false)
        renderCandidates(showTabs: false)
    }

    private func replaceDisplayed(with value: String, commit: Bool) {
        if stringSetting("marked_text_setting_beta", fallback: "disabled") != "disabled" {
            textDocumentProxy.setMarkedText(value, selectedRange: NSRange(location: value.utf16.count, length: 0))
            if commit { textDocumentProxy.unmarkText() }
        } else {
            for _ in lastDisplayed { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(value)
        }
        lastDisplayed = commit ? "" : value
    }

    private func commitCandidate(_ index: Int) {
        guard candidates.indices.contains(index) else { return }
        let selected = candidates[index]
        let report = makeReport(selected: selected, index: index)
        replaceDisplayed(with: selected, commit: true)
        conversionEngine?.commit(
            candidateText: selected,
            learningMode: intSetting("memory_learining_styple_setting", fallback: 0)
        )
        resetComposition()
        renderCandidates()
        maybeOfferReport(report)
    }

    private func commitComposition() {
        guard !composing.isEmpty || !rawRoman.isEmpty else { return }
        let selected = buildCandidates().first ?? composing
        replaceDisplayed(with: selected, commit: true)
        conversionEngine?.commit(
            candidateText: selected,
            learningMode: intSetting("memory_learining_styple_setting", fallback: 0)
        )
        resetComposition()
        renderCandidates()
    }

    private func directCommit(_ value: String) {
        commitComposition()
        textDocumentProxy.insertText(value)
    }

    private func delete() {
        if layout == "qwerty", !rawRoman.isEmpty {
            rawRoman.removeLast()
            composing = romanToHiragana(rawRoman)
        } else if !composing.isEmpty {
            composing.removeLast()
        } else {
            textDocumentProxy.deleteBackward()
            return
        }
        if composing.isEmpty {
            replaceDisplayed(with: "", commit: true)
            resetComposition()
            renderCandidates()
        } else {
            updateComposition()
        }
    }

    private func space() {
        if composing.isEmpty, rawRoman.isEmpty {
            textDocumentProxy.insertText(" ")
        } else {
            commitComposition()
        }
    }

    private func enter() {
        commitComposition()
        textDocumentProxy.insertText("\n")
    }

    private func toggleShift() {
        if shift { capsLock.toggle() }
        shift = !shift || capsLock
        renderKeyboard()
    }

    private func setMode(_ newMode: String) {
        commitComposition()
        mode = newMode
        activeCustomTab = nil
        switch newMode {
        case "japanese": layout = stringSetting("keyboard_type", fallback: "flick")
        case "english": layout = stringSetting("keyboard_type_en", fallback: "qwerty")
        default: layout = "qwerty"
        }
        renderCandidates()
        renderKeyboard()
    }

    private func handleFlickValue(_ value: String, definition: FlickDefinition) {
        feedback()
        guard let action = definition.action else {
            input(value)
            return
        }
        switch action {
        case "delete": delete()
        case "space": space()
        case "enter": enter()
        case "symbols": setMode("symbols")
        case "japanese": setMode("japanese")
        case "kogana": transformLastCharacter()
        case "nextKeyboard": advanceToNextInputMode()
        default: break
        }
    }

    private func transformLastCharacter() {
        guard let last = composing.last else { return }
        let value = smallKana[String(last)] ?? String(last)
        composing.removeLast()
        composing += value
        updateComposition()
    }

    private func dispatch(_ action: [String: Any]?) {
        guard let action else { return }
        let type = action["type"] as? String ?? "input"
        let value = action["value"] as? String ?? ""
        switch type {
        case "input": directCommit(value)
        case "delete":
            for _ in 0 ..< (Int(value) ?? 1).clamped(to: 1 ... 100) { delete() }
        case "enter": enter()
        case "space": space()
        case "moveCursor": textDocumentProxy.adjustTextPosition(byCharacterOffset: Int(value) ?? 0)
        case "switchLayout": setMode(value == "english" ? "english" : "japanese")
        case "paste":
            if hasFullAccess, let value = UIPasteboard.general.string { directCommit(value) }
        case "toggleTabBar": renderCandidates(showTabs: true)
        case "dismiss": dismissKeyboard()
        default: break
        }
    }

    private func buildCandidates() -> [String] {
        guard !composing.isEmpty else { return [] }
        var result: [String] = []
        if let dictionary = state["userDictionary"] as? [[String: Any]] {
            for entry in dictionary where entry["ruby"] as? String == composing {
                if entry["isTemplateMode"] as? Bool == true {
                    result.append(renderTemplate(entry["formatLiteral"] as? String ?? ""))
                } else if let word = entry["word"] as? String {
                    result.append(word)
                }
            }
        }
        let zenzai = zenzaiConfiguration()
        result.append(contentsOf: conversionEngine?.candidates(
            reading: composing,
            rawRoman: layout == "qwerty" ? rawRoman : nil,
            leftContext: textDocumentProxy.documentContextBeforeInput,
            rightContext: textDocumentProxy.documentContextAfterInput,
            modelURL: zenzai?.url,
            inferenceLimit: zenzai?.inferenceLimit ?? 1,
            learningMode: intSetting("memory_learining_styple_setting", fallback: 0),
            fullWidthRomanCandidate: boolSetting("full_roman_candidate", fallback: true),
            halfWidthKanaCandidate: boolSetting("half_kana_candidate", fallback: true),
            unicodeCandidate: boolSetting("unicode_candidate", fallback: true),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0.1"
        ) ?? [])
        if boolSetting("use_OS_user_dict", fallback: true) {
            result.append(contentsOf: osLexicon[composing] ?? [])
        }
        result.append(contentsOf: Self.systemDictionary[composing] ?? [])
        result.append(composing)
        let katakana = hiraganaToKatakana(composing)
        if katakana != composing { result.append(katakana) }
        if boolSetting("emoji_dictionary_enabled", fallback: true) {
            result.append(contentsOf: Self.emojiDictionary[composing] ?? [])
        }
        if boolSetting("kaomoji_dictionary_enabled", fallback: false) {
            result.append(contentsOf: Self.kaomojiDictionary[composing] ?? [])
        }
        if layout == "qwerty", boolSetting("roman_english_candidate", fallback: true), !rawRoman.isEmpty {
            result.append(rawRoman)
        }
        var seen = Set<String>()
        return result.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func zenzaiConfiguration() -> (url: URL, inferenceLimit: Int)? {
        guard boolSetting("enable_zenzai", fallback: false) else { return nil }
        let effort = intSetting("zenzai_effort", fallback: 1)
        let size = effort == 0 ? "xsmall" : "small"
        guard let url = Bundle.main.url(
            forResource: "ggml-model-Q5_K_M",
            withExtension: "gguf",
            subdirectory: "zenz-v3.2-\(size)-gguf"
        ) else { return nil }
        let limit = switch effort {
        case 0: 2
        case 2: 3
        default: 1
        }
        return (url, limit)
    }

    private func makeReport(selected: String, index: Int) -> WrongConversionReport {
        WrongConversionReport(
            suggested: candidates.first ?? selected,
            selected: selected,
            selectedIndex: index,
            reading: composing,
            rawInput: layout == "qwerty" ? rawRoman : composing,
            inputStyle: layout == "qwerty" ? "roman2kana" : "direct",
            leftContext: textDocumentProxy.documentContextBeforeInput ?? "",
            rightContext: textDocumentProxy.documentContextAfterInput ?? "",
            japaneseLayout: layout,
            textContentType: textDocumentProxy.textContentType?.rawValue ?? "nil",
            returnKeyType: String(textDocumentProxy.returnKeyType.rawValue)
        )
    }

    private func maybeOfferReport(_ report: WrongConversionReport) {
        guard hasFullAccess,
              boolSetting("enable_wrong_conversion_report", fallback: false),
              report.selectedIndex != 0,
              !report.reading.isEmpty,
              report.reading.unicodeScalars.allSatisfy(Self.isReportableInput),
              !(report.suggested.hasPrefix(report.selected) && report.suggested.count > report.selected.count) else { return }
        let denominator = intSetting("wrong_conversion_report_frequency", fallback: 10)
        guard denominator <= 1 || Int.random(in: 1 ... denominator) == 1 else { return }
        let key = report.reading + "\u{1f}" + report.selected
        let history = state["reportedWrongConversionPairs"] as? [String] ?? []
        guard !history.contains(key) else { return }
        pendingReport = report
        showReportPrompt(report)
    }

    private func showReportPrompt(_ report: WrongConversionReport) {
        candidateStack.removeAllArrangedSubviews()
        candidateStack.addArrangedSubview(makeCandidateButton("「\(report.selected)」を選択", action: {}))
        candidateStack.addArrangedSubview(makeCandidateButton("改善レポートを送信", action: submitPendingReport))
        candidateStack.addArrangedSubview(makeCandidateButton("詳細") { [weak self] in self?.showReportDetails(report) })
        candidateStack.addArrangedSubview(makeCandidateButton("×") { [weak self] in
            self?.pendingReport = nil
            self?.renderCandidates()
        })
    }

    private func showReportDetails(_ report: WrongConversionReport) {
        candidateStack.removeAllArrangedSubviews()
        candidateStack.addArrangedSubview(makeCandidateButton("第一候補: \(report.suggested)", action: {}))
        candidateStack.addArrangedSubview(makeCandidateButton("選択: \(report.selected)", action: {}))
        candidateStack.addArrangedSubview(makeCandidateButton("入力: \(report.reading)", action: {}))
        if boolSetting("wrong_conversion_include_context", fallback: false) {
            candidateStack.addArrangedSubview(makeCandidateButton("前: \(report.leftContext.suffix(10))", action: {}))
            candidateStack.addArrangedSubview(makeCandidateButton("後: \(report.rightContext.prefix(10))", action: {}))
        }
        candidateStack.addArrangedSubview(makeCandidateButton("送信", action: submitPendingReport))
        candidateStack.addArrangedSubview(makeCandidateButton("戻る") { [weak self] in self?.showReportPrompt(report) })
    }

    private func showLegacyReportPrompt(_ candidate: String, index: Int) {
        let ruby = composing
        candidateStack.removeAllArrangedSubviews()
        candidateStack.addArrangedSubview(makeCandidateButton("「\(candidate)」を誤変換として報告", action: {}))
        candidateStack.addArrangedSubview(makeCandidateButton("送信") { [weak self] in
            guard let self else { return }
            candidateStack.removeAllArrangedSubviews()
            candidateStack.addArrangedSubview(makeCandidateButton("送信中…", action: {}))
            ReportClient.submitLegacyWrongConversion(
                candidate: candidate,
                ruby: ruby,
                index: index,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown Version",
                learningEnabled: intSetting("memory_learining_styple_setting", fallback: 0) != 2
            ) { [weak self] success in
                DispatchQueue.main.async {
                    guard let self else { return }
                    candidateStack.removeAllArrangedSubviews()
                    candidateStack.addArrangedSubview(makeCandidateButton(success ? "レポートを送信しました" : "送信に失敗しました", action: {}))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                        self?.renderCandidates(showTabs: false)
                    }
                }
            }
        })
        candidateStack.addArrangedSubview(makeCandidateButton("キャンセル") { [weak self] in
            self?.renderCandidates(showTabs: false)
        })
    }

    private func submitPendingReport() {
        guard let report = pendingReport else { return }
        candidateStack.removeAllArrangedSubviews()
        candidateStack.addArrangedSubview(makeCandidateButton("送信中…", action: {}))
        ReportClient.submit(
            report: report,
            settings: settings,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown Version"
        ) { [weak self] success in
            DispatchQueue.main.async {
                guard let self else { return }
                if success { registerReportedPair(report) }
                pendingReport = nil
                candidateStack.removeAllArrangedSubviews()
                candidateStack.addArrangedSubview(makeCandidateButton(success ? "レポートを送信しました" : "送信に失敗しました", action: {}))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.renderCandidates() }
            }
        }
    }

    private func registerReportedPair(_ report: WrongConversionReport) {
        let key = report.reading + "\u{1f}" + report.selected
        var history = (state["reportedWrongConversionPairs"] as? [String] ?? []).filter { $0 != key }
        history.append(key)
        if history.count > 2048 { history.removeFirst(history.count - 2048) }
        state["reportedWrongConversionPairs"] = history
        saveState()
    }

    private func showEmoji() {
        candidateStack.removeAllArrangedSubviews()
        for value in ["😀", "😃", "😊", "😂", "🥰", "😍", "😭", "😡", "👍", "🙏", "❤️", "🎉", "✨", "⭐️"] {
            candidateStack.addArrangedSubview(makeCandidateButton(value) { [weak self] in self?.directCommit(value) })
        }
    }

    private func showClipboardHistory() {
        guard hasFullAccess else { return }
        var history = state["clipboardHistory"] as? [String] ?? []
        if let current = UIPasteboard.general.string, !current.isEmpty {
            history.removeAll(where: { $0 == current })
            history.insert(current, at: 0)
        }
        history = Array(history.prefix(50))
        state["clipboardHistory"] = history
        saveState()
        candidateStack.removeAllArrangedSubviews()
        if history.isEmpty {
            candidateStack.addArrangedSubview(makeCandidateButton("履歴はありません", action: {}))
        } else {
            for value in history.prefix(20) {
                candidateStack.addArrangedSubview(makeCandidateButton(String(value.prefix(32))) { [weak self] in self?.directCommit(value) })
            }
        }
    }

    private func saveState() {
        guard let data = try? JSONSerialization.data(withJSONObject: state),
              let value = String(data: data, encoding: .utf8) else { return }
        UserDefaults(suiteName: "group.com.azooKey.keyboard")?.set(value, forKey: "azookey_flutter_state")
    }

    private func customTabName(_ id: String) -> String {
        let tabs = state["customTabs"] as? [[String: Any]] ?? []
        return tabs.first(where: { $0["id"] as? String == id })?["name"] as? String ?? "タブ"
    }

    private func renderTemplate(_ template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = template
        return formatter.string(from: Date())
    }

    private func resetComposition() {
        composing = ""
        rawRoman = ""
        lastDisplayed = ""
        candidates = []
    }

    private func loadOSLexiconIfNeeded() {
        guard boolSetting("use_OS_user_dict", fallback: true) else {
            osLexicon = [:]
            return
        }
        requestSupplementaryLexicon { [weak self] lexicon in
            var entries: [String: [String]] = [:]
            for entry in lexicon.entries {
                entries[entry.userInput, default: []].append(entry.documentText)
            }
            DispatchQueue.main.async {
                self?.osLexicon = entries
            }
        }
    }

    private func feedback() {
        if boolSetting("enable_key_haptics", fallback: false), hasFullAccess {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if boolSetting("sound_enable_setting", fallback: false) {
            UIDevice.current.playInputClick()
        }
    }

    private func makeRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 4
        row.distribution = .fillEqually
        return row
    }

    private func makeButton(_ title: String, special: Bool = false, action: @escaping () -> Void) -> UIButton {
        let button = ClosureButton(type: .system)
        button.action = { [weak self] in
            action()
            self?.feedback()
        }
        button.setTitle(title, for: .normal)
        style(button, special: special)
        return button
    }

    private func style(_ button: UIButton, special: Bool) {
        button.setTitleColor(palette.text, for: .normal)
        button.backgroundColor = special ? palette.special : palette.key
        button.layer.cornerRadius = 6
        let fontSize = doubleSetting("key_view_font_size", fallback: -1)
        button.titleLabel?.font = .systemFont(ofSize: fontSize > 0 ? fontSize : 17)
    }

    private func makeCandidateButton(_ title: String, action: @escaping () -> Void) -> ClosureButton {
        let button = ClosureButton(type: .system)
        button.action = action
        button.setTitle(title, for: .normal)
        button.setTitleColor(palette.text, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: CGFloat(doubleSetting("result_view_font_size", fallback: 16).positiveOr(16)))
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)
        return button
    }

    private func boolSetting(_ key: String, fallback: Bool) -> Bool { settings[key] as? Bool ?? fallback }
    private func stringSetting(_ key: String, fallback: String) -> String { settings[key] as? String ?? fallback }
    private func intSetting(_ key: String, fallback: Int) -> Int { (settings[key] as? NSNumber)?.intValue ?? fallback }
    private func doubleSetting(_ key: String, fallback: Double) -> Double { (settings[key] as? NSNumber)?.doubleValue ?? fallback }

    private func color(_ value: Any?, fallback: UInt32) -> UIColor {
        let number = (value as? NSNumber)?.uint32Value ?? fallback
        return UIColor(
            red: CGFloat((number >> 16) & 0xff) / 255,
            green: CGFloat((number >> 8) & 0xff) / 255,
            blue: CGFloat(number & 0xff) / 255,
            alpha: CGFloat((number >> 24) & 0xff) / 255
        )
    }

    private static let systemDictionary: [String: [String]] = [
        "あい": ["愛", "藍", "相"], "あした": ["明日"], "ありがとう": ["ありがとう", "有難う"],
        "いま": ["今", "居間"], "おねがい": ["お願い"], "きょう": ["今日", "京"],
        "こんにちは": ["今日は", "こんにちは"], "じかん": ["時間"], "せってい": ["設定"],
        "だいじょうぶ": ["大丈夫"], "でんわ": ["電話"], "にほん": ["日本", "二本"],
        "にほんご": ["日本語"], "へんかん": ["変換"], "ほんじつ": ["本日"], "わたし": ["私"],
    ]
    private static let emojiDictionary = ["えがお": ["😊", "😄", "🙂"], "はーと": ["❤️", "💕", "💙"], "ほし": ["⭐️", "🌟", "✨"]]
    private static let kaomojiDictionary = ["えがお": ["( ´ ▽ ` )", "(^_^)"], "かなしい": ["( ; _ ; )", "(´；ω；`)"]]
    private static func isReportableInput(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3041 ... 0x3096, 0x30 ... 0x39, 0x41 ... 0x5a, 0x61 ... 0x7a: true
        default: false
        }
    }
    private let smallKana = ["あ": "ぁ", "ぁ": "あ", "い": "ぃ", "ぃ": "い", "う": "ぅ", "ぅ": "ゔ", "ゔ": "う", "え": "ぇ", "ぇ": "え", "お": "ぉ", "ぉ": "お", "つ": "っ", "っ": "づ", "づ": "つ", "や": "ゃ", "ゃ": "や", "ゆ": "ゅ", "ゅ": "ゆ", "よ": "ょ", "ょ": "よ", "か": "が", "が": "か", "は": "ば", "ば": "ぱ", "ぱ": "は"]
}

private final class ClosureButton: UIButton {
    var action: (() -> Void)?
    var longPressAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:))))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:))))
    }

    @objc private func tapped() { action?() }
    @objc private func longPressed(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began { longPressAction?() }
    }
}

private struct FlickDefinition {
    let label: String
    let values: [String]
    let action: String?

    init(_ label: String, _ values: [String]) {
        self.label = label
        self.values = values
        self.action = nil
    }

    static func action(_ label: String, _ action: String) -> Self {
        Self(label: label, values: [label], action: action)
    }

    private init(label: String, values: [String], action: String?) {
        self.label = label
        self.values = values
        self.action = action
    }
}

private final class FlickButton: UIButton {
    private let definition: FlickDefinition
    private let sensitivity: CGFloat
    private let callback: (String) -> Void
    private var start = CGPoint.zero

    init(definition: FlickDefinition, sensitivity: CGFloat, callback: @escaping (String) -> Void) {
        self.definition = definition
        self.sensitivity = sensitivity
        self.callback = callback
        super.init(frame: .zero)
        setTitle(definition.label, for: .normal)
    }

    required init?(coder: NSCoder) { nil }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        start = touches.first?.location(in: self) ?? .zero
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        let end = touches.first?.location(in: self) ?? start
        let dx = end.x - start.x
        let dy = end.y - start.y
        let threshold = 20 * sensitivity
        let index: Int
        if abs(dx) < threshold, abs(dy) < threshold {
            index = 0
        } else if abs(dx) > abs(dy) {
            index = dx < 0 ? 1 : 3
        } else {
            index = dy < 0 ? 2 : 4
        }
        callback(definition.values[min(index, definition.values.count - 1)])
    }
}

private final class CustomFlickButton: UIButton {
    private let key: [String: Any]
    private let sensitivity: CGFloat
    private let callback: ([String: Any]?) -> Void
    private var start = CGPoint.zero
    private var longPressWorkItem: DispatchWorkItem?
    private var didLongPress = false

    init(
        key: [String: Any],
        sensitivity: CGFloat,
        callback: @escaping ([String: Any]?) -> Void
    ) {
        self.key = key
        self.sensitivity = sensitivity
        self.callback = callback
        super.init(frame: .zero)
        setTitle(key["label"] as? String ?? key["name"] as? String ?? "", for: .normal)
    }

    required init?(coder: NSCoder) { nil }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        start = touches.first?.location(in: self) ?? .zero
        didLongPress = false
        let work = DispatchWorkItem { [weak self] in
            guard let self, let action = key["longPress"] as? [String: Any] else { return }
            didLongPress = true
            callback(action)
        }
        longPressWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        longPressWorkItem?.cancel()
        guard !didLongPress else { return }
        let end = touches.first?.location(in: self) ?? start
        let dx = end.x - start.x
        let dy = end.y - start.y
        let direction: String
        let threshold = 20 * sensitivity
        if abs(dx) < threshold, abs(dy) < threshold {
            direction = "tap"
        } else if abs(dx) > abs(dy) {
            direction = dx < 0 ? "left" : "right"
        } else {
            direction = dy < 0 ? "up" : "down"
        }
        callback(key[direction] as? [String: Any] ?? key["tap"] as? [String: Any])
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressWorkItem?.cancel()
        super.touchesCancelled(touches, with: event)
    }
}

private struct KeyboardPalette {
    let background: UIColor
    let key: UIColor
    let special: UIColor
    let text: UIColor
    let accent: UIColor

    static let light = KeyboardPalette(background: UIColor(argb: 0xffd1d5db), key: .white, special: UIColor(argb: 0xffadb5bd), text: UIColor(argb: 0xff111827), accent: UIColor(argb: 0xff2563eb))
    static let dark = KeyboardPalette(background: UIColor(argb: 0xff111827), key: UIColor(argb: 0xff374151), special: UIColor(argb: 0xff1f2937), text: .white, accent: UIColor(argb: 0xff60a5fa))
}

private extension UIColor {
    convenience init(argb: UInt32) {
        self.init(red: CGFloat((argb >> 16) & 0xff) / 255, green: CGFloat((argb >> 8) & 0xff) / 255, blue: CGFloat(argb & 0xff) / 255, alpha: CGFloat((argb >> 24) & 0xff) / 255)
    }
}

private extension UIStackView {
    func removeAllArrangedSubviews() {
        for view in arrangedSubviews {
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

private extension Double {
    func positiveOr(_ fallback: Double) -> Double { self > 0 ? self : fallback }
}

private func romanToHiragana(_ input: String) -> String {
    let lower = input.lowercased()
    var result = ""
    var index = lower.startIndex
    while index < lower.endIndex {
        let next = lower.index(after: index)
        let current = lower[index]
        if next < lower.endIndex, current == lower[next], "bcdfghjklmpqrstvwxyz".contains(current), current != "n" {
            result += "っ"
            index = next
            continue
        }
        if current == "n", next < lower.endIndex, !"aiueoyn".contains(lower[next]) {
            result += "ん"
            index = next
            continue
        }
        var matched = false
        for length in [4, 3, 2, 1] {
            guard let end = lower.index(index, offsetBy: length, limitedBy: lower.endIndex) else { continue }
            let key = String(lower[index ..< end])
            if let value = romanMap[key] {
                result += value
                index = end
                matched = true
                break
            }
        }
        if !matched {
            result.append(current)
            index = next
        }
    }
    if result.hasSuffix("n") {
        result.removeLast()
        result += "ん"
    }
    return result
}

private func hiraganaToKatakana(_ value: String) -> String {
    String(value.unicodeScalars.map { scalar in
        if (0x3041 ... 0x3096).contains(scalar.value), let converted = UnicodeScalar(scalar.value + 0x60) {
            return Character(converted)
        }
        return Character(scalar)
    })
}

private let romanMap: [String: String] = [
    "kya": "きゃ", "kyu": "きゅ", "kyo": "きょ", "gya": "ぎゃ", "gyu": "ぎゅ", "gyo": "ぎょ", "sha": "しゃ", "shu": "しゅ", "sho": "しょ", "cha": "ちゃ", "chu": "ちゅ", "cho": "ちょ", "nya": "にゃ", "nyu": "にゅ", "nyo": "にょ", "hya": "ひゃ", "hyu": "ひゅ", "hyo": "ひょ", "mya": "みゃ", "myu": "みゅ", "myo": "みょ", "rya": "りゃ", "ryu": "りゅ", "ryo": "りょ", "fa": "ふぁ", "fi": "ふぃ", "fe": "ふぇ", "fo": "ふぉ", "shi": "し", "chi": "ち", "tsu": "つ",
    "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ", "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご", "sa": "さ", "si": "し", "su": "す", "se": "せ", "so": "そ", "za": "ざ", "zi": "じ", "ji": "じ", "zu": "ず", "ze": "ぜ", "zo": "ぞ", "ta": "た", "ti": "ち", "tu": "つ", "te": "て", "to": "と", "da": "だ", "di": "ぢ", "du": "づ", "de": "で", "do": "ど", "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の", "ha": "は", "hi": "ひ", "hu": "ふ", "fu": "ふ", "he": "へ", "ho": "ほ", "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ", "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ", "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も", "ya": "や", "yu": "ゆ", "yo": "よ", "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ", "wa": "わ", "wo": "を", "nn": "ん", "ltu": "っ", "xtu": "っ", "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お", "-": "ー", ",": "、", ".": "。",
]
