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
    private var cursorBarVisible = false
    private weak var cursorBarView: CursorBarView?
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
        cursorBarVisible = false
        cursorBarView = nil
        mode = "japanese"
        layout = stringSetting("keyboard_type", fallback: "flick")
        renderCandidates()
        renderKeyboard()
    }

    override func textWillChange(_ textInput: (any UITextInput)?) {
        super.textWillChange(textInput)
        reloadState()
        refreshCursorBar()
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
                [.action("☆123", "symbols", target: "symbols_tab"), .init("@#/&_", ["@", "#", "/", "&", "_"]), .init("ABC", ["a", "b", "c", "2", ""]), .init("DEF", ["d", "e", "f", "3", ""]), .delete("⌫")],
                [.action("ABC", "english", target: "abc_tab"), .init("GHI", ["g", "h", "i", "4", ""]), .init("JKL", ["j", "k", "l", "5", ""]), .init("MNO", ["m", "n", "o", "6", ""]), .space("空白")],
                [.action("あいう", "japanese", target: "hira_tab"), .init("PQRS", ["p", "q", "r", "s", "7"]), .init("TUV", ["t", "u", "v", "8", ""]), .init("WXYZ", ["w", "x", "y", "z", "9"]), .action("改行", "enter")],
                [.action("🌐", "nextKeyboard"), .action("a/A", "shiftEnglish"), .init("'\"()", ["'", "\"", "(", ")", ""]), .init(".,?!", [".", ",", "?", "!", "'"], target: "kana_symbols"), .action("改行", "enter")],
            ]
        } else {
            rows = [
                [.action("☆123", "symbols", target: "symbols_tab"), .init("あ", ["あ", "い", "う", "え", "お"]), .init("か", ["か", "き", "く", "け", "こ"]), .init("さ", ["さ", "し", "す", "せ", "そ"]), .delete("⌫")],
                [.action("ABC", "english", target: "abc_tab"), .init("た", ["た", "ち", "つ", "て", "と"]), .init("な", ["な", "に", "ぬ", "ね", "の"]), .init("は", ["は", "ひ", "ふ", "へ", "ほ"]), .space("空白")],
                [.action("あいう", "japanese", target: "hira_tab"), .init("ま", ["ま", "み", "む", "め", "も"]), .init("や", ["や", "「", "ゆ", "」", "よ"]), .init("ら", ["ら", "り", "る", "れ", "ろ"]), .action("改行", "enter")],
                [.action("🌐", "nextKeyboard"), .action("小ﾞﾟ", "kogana", target: "kogana"), .init("わ", ["わ", "を", "ん", "ー", "〜"]), .init("､｡?!", ["、", "。", "？", "！", ""], target: "kana_symbols"), .action("改行", "enter")],
            ]
        }
        for definitions in rows {
            let row = makeRow()
            for definition in definitions {
                if let target = definition.customTarget, let custom = customKeyForTarget(target) {
                    row.addArrangedSubview(makeCustomButton(custom))
                    continue
                }
                let button = FlickButton(definition: definition, sensitivity: CGFloat(doubleSetting("flick_sensitivity_setting", fallback: 1))) { [weak self] value in self?.handleFlickValue(value, definition: definition) }
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
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if renderCustard(normalizedID) { return }
        guard let tabs = state["customTabs"] as? [[String: Any]],
              let tab = tabs.first(where: { ($0["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedID }),
              let keys = tab["keys"] as? [[String: Any]] else {
            let bottom = makeRow()
            bottom.addArrangedSubview(makeButton("タブ", special: true) { [weak self] in self?.renderCandidates(showTabs: true) })
            bottom.addArrangedSubview(makeButton("あいう", special: true) { [weak self] in self?.setMode("japanese") })
            keyboardStack.addArrangedSubview(bottom)
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

    @discardableResult
    private func renderCustard(_ id: String) -> Bool {
        guard let custards = state["custards"] as? [[String: Any]],
              let custard = custards.first(where: {
                  ($0["identifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == id
              }),
              let interface = custard["interface"] as? [String: Any],
              let layout = interface["key_layout"] as? [String: Any],
              let elements = interface["keys"] as? [[String: Any]] else {
            return false
        }
        let keyStyle = interface["key_style"] as? String ?? "tenkey_style"
        let layoutType = layout["type"] as? String ?? "grid_fit"
        let rowCount = (layout["row_count"] as? NSNumber)?.doubleValue ?? 4
        let columnCount = (layout["column_count"] as? NSNumber)?.doubleValue ?? 5
        let custardView: CustardLayoutView
        if layoutType == "grid_scroll" {
            let sorted = elements
                .filter { $0["specifier_type"] as? String == "grid_scroll" }
                .sorted {
                    let lhs = (($0["specifier"] as? [String: Any])?["index"] as? NSNumber)?.intValue ?? .max
                    let rhs = (($1["specifier"] as? [String: Any])?["index"] as? NSNumber)?.intValue ?? .max
                    return lhs < rhs
                }
            custardView = CustardLayoutView(
                scrollDirection: layout["direction"] as? String ?? "vertical",
                crossCount: max(1, Int(rowCount)),
                visibleCount: max(1, CGFloat(columnCount))
            )
            for element in sorted {
                custardView.append(makeCustardKey(element, keyStyle: keyStyle, variationsEnabled: false))
            }
        } else {
            // Custard's row_count is the horizontal cell count and
            // column_count is the vertical cell count. Coordinates outside
            // that declared grid are not part of the layout; skip them
            // instead of moving them to the last row/column.
            let columns = min(40, max(1, Int(rowCount)))
            let rows = min(40, max(1, Int(columnCount)))
            custardView = CustardLayoutView(columns: columns, rows: rows)
            for element in elements where element["specifier_type"] as? String == "grid_fit" {
                guard let specifier = element["specifier"] as? [String: Any] else { continue }
                let x = CGFloat((specifier["x"] as? NSNumber)?.doubleValue ?? 0)
                let y = CGFloat((specifier["y"] as? NSNumber)?.doubleValue ?? 0)
                guard x >= 0, y >= 0, x < CGFloat(columns), y < CGFloat(rows) else { continue }
                let width = min(max(0.01, CGFloat((specifier["width"] as? NSNumber)?.doubleValue ?? 1)), CGFloat(columns) - x)
                let height = min(max(0.01, CGFloat((specifier["height"] as? NSNumber)?.doubleValue ?? 1)), CGFloat(rows) - y)
                custardView.append(
                    makeCustardKey(element, keyStyle: keyStyle),
                    x: x,
                    y: y,
                    width: width,
                    height: height
                )
            }
        }
        keyboardStack.addArrangedSubview(custardView)
        return true
    }

    private func makeCustardKey(
        _ element: [String: Any],
        keyStyle: String,
        variationsEnabled: Bool = true
    ) -> UIButton {
        let key = element["key"] as? [String: Any] ?? [:]
        if element["key_type"] as? String == "system" {
            return makeCustardSystemKey(key["type"] as? String ?? "")
        }
        let design = key["design"] as? [String: Any] ?? [:]
        let label = design["label"] as? [String: Any]
        let directionTitles = custardFlickDirectionLabels(
            key: key,
            label: label,
            variationsEnabled: variationsEnabled
        )
        let button = CustardButton(
            title: directionTitles.isEmpty ? custardLabel(label) : custardPrimaryLabel(label),
            directionTitles: directionTitles,
            key: key,
            keyStyle: keyStyle,
            variationsEnabled: variationsEnabled,
            sensitivity: CGFloat(doubleSetting("flick_sensitivity_setting", fallback: 1))
        ) { [weak self] actions in
            self?.dispatch(actions)
            self?.feedback()
        }
        let color = design["color"] as? String ?? "normal"
        style(button, special: color == "special" || color == "unimportant")
        if color == "selected" { button.backgroundColor = palette.accent }
        return button
    }

    private func makeCustardSystemKey(_ type: String) -> UIButton {
        let target: String? = switch type {
        case "flick_kogaki": "kogana"
        case "flick_kutoten": "kana_symbols"
        case "flick_hira_tab": "hira_tab"
        case "flick_abc_tab": "abc_tab"
        case "flick_star123_tab": "symbols_tab"
        default: nil
        }
        if let target, let custom = customKeyForTarget(target) {
            return makeCustomButton(custom)
        }
        switch type {
        case "change_keyboard": return makeButton("🌐", special: true) { [weak self] in self?.advanceToNextInputMode() }
        case "qwerty_language_switch": return makeButton("あA", special: true) { [weak self] in
            guard let self else { return }
            setMode(mode == "japanese" ? "english" : "japanese")
        }
        case "qwerty_shift": return makeButton(capsLock ? "⇪" : "⇧", special: true, action: toggleShift)
        case "qwerty_dynamic_change": return makeButton("☆123", special: true) { [weak self] in
            guard let self else { return }
            setMode(mode == "symbols" ? "english" : "symbols")
        }
        case "qwerty_space": return makeButton(composing.isEmpty ? "空白" : "次候補", action: selectNextCandidate)
        case "enter": return makeButton("改行", special: true, action: enter)
        case "upper_lower": return makeButton("Aa", special: true) { [weak self] in
            guard let self else { return }
            mode == "english" ? toggleShift() : transformLastCharacter()
        }
        case "next_candidate": return makeButton(composing.isEmpty ? "空白" : "次候補", special: true) { [weak self] in self?.selectNextCandidate() }
        case "flick_kogaki": return makeButton("小ﾞﾟ", special: true, action: transformLastCharacter)
        case "flick_kutoten":
            let definition = FlickDefinition("､｡?!", ["、", "。", "？", "！", ""])
            let button = FlickButton(definition: definition, sensitivity: CGFloat(doubleSetting("flick_sensitivity_setting", fallback: 1))) { [weak self] value in self?.input(value) }
            style(button, special: true)
            return button
        case "flick_hira_tab": return makeButton("あいう", special: true) { [weak self] in self?.setMode("japanese") }
        case "flick_abc_tab": return makeButton("ABC", special: true) { [weak self] in self?.setMode("english") }
        case "flick_star123_tab": return makeButton("☆123", special: true) { [weak self] in self?.setMode("symbols") }
        default: return makeButton("", special: true) {}
        }
    }

    private func selectNextCandidate() {
        if candidates.isEmpty {
            space()
            return
        }
        let current = candidates.firstIndex(of: lastDisplayed) ?? -1
        let next = (current + 1) % candidates.count
        replaceDisplayed(with: candidates[next], commit: false)
        renderCandidates(showTabs: false)
    }

    private func custardLabel(_ label: [String: Any]?) -> String {
        guard let label else { return "" }
        if let text = label["text"] as? String { return text }
        if let image = label["system_image"] as? String { return systemImageLabel(image) }
        switch label["type"] as? String {
        case "main_and_sub":
            return "\(label["main"] as? String ?? "")\n\(label["sub"] as? String ?? "")"
        case "main_and_directions": return label["main"] as? String ?? ""
        case "system_image": return systemImageLabel(label["system_image"] as? String ?? "")
        default: return label["text"] as? String ?? ""
        }
    }

    private func custardPrimaryLabel(_ label: [String: Any]?) -> String {
        guard let label else { return "" }
        switch label["type"] as? String {
        case "main_and_sub", "main_and_directions": return label["main"] as? String ?? ""
        default: return custardLabel(label)
        }
    }

    private func custardFlickDirectionLabels(
        key: [String: Any],
        label: [String: Any]?,
        variationsEnabled: Bool
    ) -> [String: String] {
        guard variationsEnabled else { return [:] }
        let variations = (key["variations"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "flick_variation" }
        let declaredDirections: [String: Any]?
        if label?["type"] as? String == "main_and_directions" {
            declaredDirections = label?["directions"] as? [String: Any]
        } else {
            declaredDirections = nil
        }
        var values: [String: String] = [:]
        for direction in ["left", "top", "right", "bottom"] {
            let variation = variations.first(where: { $0["direction"] as? String == direction })
            let variationKey = variation?["key"] as? [String: Any]
            let design = variationKey?["design"] as? [String: Any]
            let variationLabel = custardLabel(design?["label"] as? [String: Any])
            let actions = variationKey?["press_actions"] as? [[String: Any]] ?? []
            let actionLabel = actionDisplayLabel(actions.first)
            let declaredLabel = declaredDirections?[direction] as? String
            let candidates: [String?] = [variationLabel, declaredLabel, actionLabel]
            if let value = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                values[direction] = value
            }
        }
        return values
    }

    private func actionDisplayLabel(_ action: [String: Any]?) -> String? {
        guard let action else { return nil }
        let value: String?
        switch action["type"] as? String ?? "input" {
        case "input": value = action["text"] as? String ?? action["value"] as? String
        case "directInput": value = action["value"] as? String
        case "direct_input": value = action["text"] as? String
        default: value = nil
        }
        return value?.isEmpty == false ? value : nil
    }

    private func systemImageLabel(_ name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmedName.lowercased() {
        case "delete.left": return "⌫"
        case "delete.right": return "⌦"
        case "xmark": return "×"
        case "globe", "globe.europe.africa": return "🌐"
        case "return", "return.left": return "↵"
        case "space": return "空白"
        case "list.bullet": return "☰"
        case "arrow.left", "chevron.left", "chevron.left.2": return "←"
        case "arrow.up": return "↑"
        case "arrow.right", "chevron.right", "chevron.right.2": return "→"
        case "arrow.down": return "↓"
        case "arrowtriangle.left.and.line.vertical.and.arrowtriangle.right": return "↔"
        case "keyboard.chevron.compact.down.fill": return "⌄"
        case "textformat.123": return "123"
        case "textformat.superscript": return "x²"
        case "face.smiling": return "🙂"
        case "doc.on.clipboard", "list.bullet.clipboard": return "📋"
        case "shift", "shift.fill": return "⇧"
        default: return trimmedName
        }
    }

    private func renderStandaloneCustomKeys() {
        let keys = Array((state["customKeys"] as? [[String: Any]] ?? [])
            .filter { ($0["target"] as? String ?? "standalone") == "standalone" }
            .prefix(8))
        guard !keys.isEmpty else { return }
        for start in stride(from: 0, to: keys.count, by: 4) {
            let row = makeRow()
            for key in keys[start ..< min(start + 4, keys.count)] {
                row.addArrangedSubview(makeCustomButton(key))
            }
            keyboardStack.addArrangedSubview(row)
        }
    }

    private func customKeyForTarget(_ target: String) -> [String: Any]? {
        (state["customKeys"] as? [[String: Any]])?.first {
            ($0["target"] as? String ?? "standalone") == target
        }
    }

    private func makeCustomButton(_ key: [String: Any]) -> UIButton {
        let directionTitles = [
            "left": actionDisplayLabel(key["left"] as? [String: Any]),
            "top": actionDisplayLabel(key["up"] as? [String: Any]),
            "right": actionDisplayLabel(key["right"] as? [String: Any]),
            "bottom": actionDisplayLabel(key["down"] as? [String: Any]),
        ].compactMapValues { $0 }
        let button = CustomFlickButton(
            key: key,
            directionTitles: directionTitles,
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
        if showTabs == true {
            cursorBarVisible = false
            cursorBarView = nil
        }
        if cursorBarVisible {
            renderCursorBar()
            return
        }
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

    private func toggleCursorBar() {
        cursorBarVisible.toggle()
        if cursorBarVisible {
            renderCursorBar()
            if boolSetting("display_cursor_bar_automatically", fallback: false) {
                cursorBarView?.scheduleAutoDismiss { [weak self] in
                    guard let self, self.cursorBarVisible else { return }
                    self.cursorBarVisible = false
                    self.cursorBarView = nil
                    self.renderCandidates()
                }
            }
        } else {
            cursorBarView = nil
            renderCandidates()
        }
    }

    private func renderCursorBar() {
        candidateStack.removeAllArrangedSubviews()
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        let bar = CursorBarView(
            before: before,
            after: after,
            palette: palette,
            fontSize: CGFloat(doubleSetting("result_view_font_size", fallback: 16).positiveOr(16)),
            onMove: { [weak self] count in
                self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: count)
                self?.refreshCursorBar()
            }
        )
        cursorBarView = bar
        bar.widthAnchor.constraint(equalTo: candidateScroll.frameLayoutGuide.widthAnchor).isActive = true
        candidateStack.addArrangedSubview(bar)
    }

    private func refreshCursorBar() {
        guard cursorBarVisible,
              let bar = cursorBarView else { return }
        bar.update(
            before: textDocumentProxy.documentContextBeforeInput ?? "",
            after: textDocumentProxy.documentContextAfterInput ?? ""
        )
    }

    private func renderTabBar() {
        var values = state["tabBar"] as? [String] ?? ["dismiss", "resize", "emoji", "japanese", "english"]
        let configured = Set(values)
        let customTabs = (state["customTabs"] as? [[String: Any]] ?? [])
            .filter { ($0["addToTabBar"] as? Bool) ?? true }
            .compactMap { tab -> String? in
                guard let rawID = tab["id"] as? String else { return nil }
                let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
                return id.isEmpty ? nil : "custom:\(id)"
            }
        for value in customTabs where !configured.contains(value) { values.append(value) }
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
                commitComposition()
                activeCustomTab = String(value.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
                mode = "japanese"
                layout = "flick"
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
        refreshCursorBar()
    }

    private func delete() {
        if layout == "qwerty", !rawRoman.isEmpty {
            rawRoman.removeLast()
            composing = romanToHiragana(rawRoman)
        } else if !composing.isEmpty {
            composing.removeLast()
        } else {
            textDocumentProxy.deleteBackward()
            refreshCursorBar()
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
        if definition.action == "space", value == "__space_longpress__" {
            if candidates.isEmpty {
                if !cursorBarVisible { toggleCursorBar() }
            } else {
                selectNextCandidate()
            }
            return
        }
        if definition.action == "space", value == "__cursor_repeat__" {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: -1)
            refreshCursorBar()
            return
        }
        guard let action = definition.action else {
            input(value)
            return
        }
        switch action {
        case "delete": value == "×" ? smartDeleteDefault() : delete()
        case "space":
            switch value {
            case "←": textDocumentProxy.adjustTextPosition(byCharacterOffset: -1); refreshCursorBar()
            case "　": input("　")
            case "\t": input("\t")
            default: space()
            }
        case "enter": enter()
        case "symbols": setMode("symbols")
        case "japanese": setMode("japanese")
        case "english": setMode("english")
        case "kogana": transformLastCharacter()
        case "shiftEnglish": toggleShift()
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
        case "input":
            if let text = action["text"] as? String { custardInput(text) } else { directCommit(value) }
        case "directInput": directCommit(value)
        case "direct_input": directCommit(action["text"] as? String ?? "")
        case "delete":
            let count = (action["count"] as? NSNumber)?.intValue ?? Int(value) ?? 1
            for _ in 0 ..< count.clamped(to: 1 ... 100) { delete() }
        case "enter": enter()
        case "space": space()
        case "moveCursor":
            textDocumentProxy.adjustTextPosition(byCharacterOffset: Int(value) ?? 0)
            refreshCursorBar()
        case "move_cursor":
            textDocumentProxy.adjustTextPosition(byCharacterOffset: (action["count"] as? NSNumber)?.intValue ?? 0)
            refreshCursorBar()
        case "switchLayout": setMode(value == "english" ? "english" : "japanese")
        case "paste", "__paste":
            if hasFullAccess, let value = UIPasteboard.general.string { directCommit(value) }
        case "replace_default": replaceDefault()
        case "replaceDefault": replaceDefault()
        case "replace_last_characters": replaceLastCharacters(action["table"] as? [String: String])
        case "smart_delete_default": smartDeleteDefault()
        case "smartDeleteDefault": smartDeleteDefault()
        case "smart_delete": smartDelete(action)
        case "select_candidate": selectCandidate(action["selection"] as? [String: Any])
        case "complete_character_form": completeCharacterForm(action["forms"] as? [String])
        case "completeCharacterForm": completeCharacterForm([value])
        case "complete": commitComposition()
        case "smart_move_cursor": smartMoveCursor(action)
        case "move_tab": moveTab(action)
        case "enable_resizing_mode": renderCandidates(showTabs: true)
        case "toggle_cursor_bar", "toggleCursorBar": toggleCursorBar()
        case "toggleTabBar", "toggle_tab_bar": renderCandidates(showTabs: true)
        case "toggle_caps_lock_state":
            capsLock.toggle()
            shift = capsLock
            renderKeyboard()
        case "toggleCapsLock":
            capsLock.toggle()
            shift = capsLock
            renderKeyboard()
        case "dismiss", "dismiss_keyboard": dismissKeyboard()
        case "launch_application": launchApplication(action)
        default: break
        }
    }

    private func dispatch(_ actions: [[String: Any]]) {
        for action in actions { dispatch(action) }
    }

    private func activeCustard() -> [String: Any]? {
        guard let id = activeCustomTab else { return nil }
        return (state["custards"] as? [[String: Any]])?.first { $0["identifier"] as? String == id }
    }

    private func custardInput(_ value: String) {
        guard !value.isEmpty else { return }
        let custard = activeCustard()
        let language = custard?["language"] as? String ?? "undefined"
        let inputStyle = custard?["input_style"] as? String ?? "direct"
        guard language == "ja_JP" else {
            directCommit(value)
            return
        }
        // Numeric Custard tabs use `input` for full-width and ASCII digits.
        // Keep those values out of kana-kanji conversion just like the built-in
        // symbols tab does, while leaving replacement-sequence markers composed.
        if value.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains) {
            directCommit(value)
            return
        }
        mode = "japanese"
        if inputStyle == "roman2kana" {
            layout = "qwerty"
            rawRoman += value.lowercased()
            composing = romanToHiragana(rawRoman)
        } else {
            layout = "flick"
            composing += value
        }
        updateComposition()
    }

    private func replaceDefault() {
        if !composing.isEmpty {
            transformLastCharacter()
            return
        }
        guard let last = textDocumentProxy.documentContextBeforeInput?.last,
              let replacement = smallKana[String(last)] else { return }
        textDocumentProxy.deleteBackward()
        textDocumentProxy.insertText(replacement)
    }

    private func replaceLastCharacters(_ table: [String: String]?) {
        guard let table else { return }
        let source = composing.isEmpty ? (textDocumentProxy.documentContextBeforeInput ?? "") : composing
        guard let match = table.keys.filter(source.hasSuffix).max(by: { $0.count < $1.count }),
              let replacement = table[match] else { return }
        if composing.isEmpty {
            for _ in match { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(replacement)
        } else {
            composing.removeLast(match.count)
            composing += replacement
            updateComposition()
        }
    }

    private func actionTargets(_ action: [String: Any]) -> [String] {
        action["targets"] as? [String] ?? Self.defaultScanTargets
    }

    private func smartDeleteDefault() {
        if !composing.isEmpty || !rawRoman.isEmpty {
            replaceDisplayed(with: "", commit: true)
            resetComposition()
            renderCandidates()
            return
        }
        smartDelete(["direction": "backward", "targets": Self.defaultScanTargets])
    }

    private func smartDelete(_ action: [String: Any]) {
        let targets = actionTargets(action)
        if action["direction"] as? String == "backward" {
            let text = textDocumentProxy.documentContextBeforeInput ?? ""
            let boundaries = targets.compactMap { target -> String.Index? in
                text.range(of: target, options: .backwards)?.upperBound
            }
            let boundary = boundaries.max() ?? text.startIndex
            for _ in text[boundary...] { textDocumentProxy.deleteBackward() }
            refreshCursorBar()
        } else {
            let text = textDocumentProxy.documentContextAfterInput ?? ""
            let distances = targets.compactMap { target -> Int? in
                guard let range = text.range(of: target) else { return nil }
                return text.distance(from: text.startIndex, to: range.lowerBound)
            }
            let count = distances.min() ?? text.count
            textDocumentProxy.adjustTextPosition(byCharacterOffset: count)
            for _ in 0 ..< count { textDocumentProxy.deleteBackward() }
            refreshCursorBar()
        }
    }

    private func smartMoveCursor(_ action: [String: Any]) {
        let targets = actionTargets(action)
        let backward = action["direction"] as? String == "backward"
        let text = backward
            ? (textDocumentProxy.documentContextBeforeInput ?? "")
            : (textDocumentProxy.documentContextAfterInput ?? "")
        let distance: Int
        if backward {
            let boundaries = targets.compactMap { target -> String.Index? in
                text.range(of: target, options: .backwards)?.upperBound
            }
            let boundary = boundaries.max() ?? text.startIndex
            distance = -text.distance(from: boundary, to: text.endIndex)
        } else {
            let distances = targets.compactMap { target -> Int? in
                guard let range = text.range(of: target) else { return nil }
                return text.distance(from: text.startIndex, to: range.lowerBound)
            }
            distance = distances.min() ?? text.count
        }
        textDocumentProxy.adjustTextPosition(byCharacterOffset: distance)
        refreshCursorBar()
    }

    private func selectCandidate(_ selection: [String: Any]?) {
        guard !candidates.isEmpty else { return }
        let current = candidates.firstIndex(of: lastDisplayed) ?? 0
        let index: Int
        switch selection?["type"] as? String {
        case "last": index = candidates.count - 1
        case "offset": index = current + ((selection?["value"] as? NSNumber)?.intValue ?? 0)
        case "exact": index = (selection?["value"] as? NSNumber)?.intValue ?? 0
        default: index = 0
        }
        replaceDisplayed(with: candidates[index.clamped(to: 0 ... candidates.count - 1)], commit: false)
        renderCandidates(showTabs: false)
    }

    private func completeCharacterForm(_ forms: [String]?) {
        guard !composing.isEmpty else { return }
        let converted: String
        switch forms?.first {
        case "hiragana": converted = katakanaToHiragana(composing)
        case "katakana": converted = hiraganaToKatakana(composing)
        case "halfwidth_katakana": converted = hiraganaToKatakana(composing).applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? composing
        case "uppercase": converted = composing.uppercased()
        case "lowercase": converted = composing.lowercased()
        default: converted = composing
        }
        replaceDisplayed(with: converted, commit: true)
        resetComposition()
        renderCandidates()
    }

    private func moveTab(_ action: [String: Any]) {
        if action["tab_type"] as? String == "custom" {
            commitComposition()
            activeCustomTab = action["identifier"] as? String
            renderCandidates()
            renderKeyboard()
            return
        }
        switch action["identifier"] as? String {
        case "user_japanese": setMode("japanese")
        case "user_english": setMode("english")
        case "flick_japanese": setForcedLayout(mode: "japanese", layout: "flick")
        case "flick_english": setForcedLayout(mode: "english", layout: "flick")
        case "qwerty_japanese": setForcedLayout(mode: "japanese", layout: "qwerty")
        case "qwerty_english": setForcedLayout(mode: "english", layout: "qwerty")
        case "flick_numbersymbols", "qwerty_numbers", "qwerty_symbols": setMode("symbols")
        case "clipboard_history_tab": showClipboardHistory()
        case "emoji_tab": showEmoji()
        case "last_tab": setMode("japanese")
        default: break
        }
    }

    private func setForcedLayout(mode: String, layout: String) {
        commitComposition()
        self.mode = mode
        self.layout = layout
        activeCustomTab = nil
        renderCandidates()
        renderKeyboard()
    }

    private func launchApplication(_ action: [String: Any]) {
        let target = action["target"] as? String ?? ""
        let value = target.contains("://") ? target : "shortcuts://run-shortcut?name=\(target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? target)"
        guard let url = URL(string: value) else { return }
        extensionContext?.open(url)
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
        guard boolSetting("enable_zenzai", fallback: true) else { return nil }
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
            returnKeyType: String(textDocumentProxy.returnKeyType?.rawValue ?? 0)
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
            self.candidateStack.removeAllArrangedSubviews()
            self.candidateStack.addArrangedSubview(self.makeCandidateButton("送信中…", action: {}))
            ReportClient.submitLegacyWrongConversion(
                candidate: candidate,
                ruby: ruby,
                index: index,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown Version",
                learningEnabled: intSetting("memory_learining_styple_setting", fallback: 0) != 2
            ) { [weak self] success in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.candidateStack.removeAllArrangedSubviews()
                    self.candidateStack.addArrangedSubview(self.makeCandidateButton(success ? "レポートを送信しました" : "送信に失敗しました", action: {}))
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
                if success { self.registerReportedPair(report) }
                self.pendingReport = nil
                self.candidateStack.removeAllArrangedSubviews()
                self.candidateStack.addArrangedSubview(self.makeCandidateButton(success ? "レポートを送信しました" : "送信に失敗しました", action: {}))
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
        if let name = tabs.first(where: { $0["id"] as? String == id })?["name"] as? String {
            return name
        }
        let custards = state["custards"] as? [[String: Any]] ?? []
        let custard = custards.first(where: { $0["identifier"] as? String == id })
        return (custard?["metadata"] as? [String: Any])?["display_name"] as? String ?? "タブ"
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
        if title == "⌫" {
            let deleteButton = RepeatDeleteButton(action: { [weak self] in
                action()
                self?.feedback()
            })
            deleteButton.setTitle(title, for: .normal)
            style(deleteButton, special: special)
            return deleteButton
        }
        if title == "space" || title == "空白" || title == "次候補" {
            let spaceButton = RepeatActionButton(
                action: { [weak self] in action(); self?.feedback() },
                longPress: { [weak self] in
                    guard let self else { return }
                    if candidates.isEmpty {
                        if !cursorBarVisible { toggleCursorBar() }
                    } else {
                        selectNextCandidate()
                    }
                }
            )
            spaceButton.setTitle(title, for: .normal)
            style(spaceButton, special: special)
            return spaceButton
        }
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
        let resolvedFontSize = fontSize > 0 ? fontSize : 17
        button.titleLabel?.font = .systemFont(ofSize: resolvedFontSize)
        (button as? DirectionalKeyButton)?.styleDirectionLabels(
            color: palette.text,
            fontSize: max(8, resolvedFontSize * 0.62)
        )
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
        "いま": ["今", "居間"], "おねがい": ["お願い"], "きょう": ["今日", "京", "きょう"],
        "こんにちは": ["今日は", "こんにちは"], "じかん": ["時間"], "せってい": ["設定"],
        "だいじょうぶ": ["大丈夫"], "でんわ": ["電話"], "にほん": ["日本", "二本"],
        "にほんご": ["日本語"], "へんかん": ["変換"], "ほんじつ": ["本日"], "わたし": ["私"],
        "これ": ["これ", "此れ"], "それ": ["それ", "其れ"], "ここ": ["ここ", "此処"],
        "こと": ["こと", "事"], "もの": ["もの", "物"], "ひと": ["人"], "ともだち": ["友達"],
        "かぞく": ["家族"], "せんせい": ["先生"], "がくせい": ["学生"], "かいしゃ": ["会社"],
        "しごと": ["仕事"], "きのう": ["昨日"], "あさ": ["朝", "麻"], "ひる": ["昼"], "よる": ["夜"],
        "てんき": ["天気"], "あめ": ["雨", "飴"], "はれ": ["晴れ"], "ゆき": ["雪", "行き"],
        "みず": ["水"], "たべもの": ["食べ物"], "のみもの": ["飲み物"], "ごはん": ["ご飯"],
        "おちゃ": ["お茶"], "でんしゃ": ["電車"], "えき": ["駅"], "くるま": ["車"],
        "びょういん": ["病院"], "だいがく": ["大学"], "がっこう": ["学校"], "ほん": ["本", "ほん"],
        "なまえ": ["名前"], "めーる": ["メール"], "ほうほう": ["方法"], "もんだい": ["問題"],
        "かいけつ": ["解決"], "せいこう": ["成功"], "しっぱい": ["失敗"], "かくにん": ["確認"],
        "せつめい": ["説明"], "へんこう": ["変更"], "ほぞん": ["保存"], "けんさく": ["検索"],
        "けっか": ["結果"], "ひつよう": ["必要"], "たいせつ": ["大切"], "べんり": ["便利"],
        "かんたん": ["簡単"], "むずかしい": ["難しい"], "おおきい": ["大きい"], "ちいさい": ["小さい"],
        "はやい": ["早い", "速い"], "おそい": ["遅い"], "いい": ["いい", "良い"], "わるい": ["悪い"],
    ]
    private static let emojiDictionary = ["えがお": ["😊", "😄", "🙂"], "はーと": ["❤️", "💕", "💙"], "ほし": ["⭐️", "🌟", "✨"]]
    private static let kaomojiDictionary = ["えがお": ["( ´ ▽ ` )", "(^_^)"], "かなしい": ["( ; _ ; )", "(´；ω；`)"]]
    private static let defaultScanTargets = ["、", "。", "！", "？", ".", ",", "．", "，", "\n"]
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
    let customTarget: String?

    init(_ label: String, _ values: [String], target: String? = nil) {
        self.label = label
        self.values = values
        self.action = nil
        self.customTarget = target
    }

    static func action(_ label: String, _ action: String, target: String? = nil) -> Self {
        Self(label: label, values: [label], action: action, customTarget: target)
    }

    static func delete(_ label: String) -> Self {
        Self(label: label, values: [label, "×", label, label, label], action: "delete", customTarget: nil)
    }

    static func space(_ label: String) -> Self {
        Self(label: label, values: [label, "←", "　", "", "\t"], action: "space", customTarget: nil)
    }

    private init(label: String, values: [String], action: String?, customTarget: String?) {
        self.label = label
        self.values = values
        self.action = action
        self.customTarget = customTarget
    }
}

/// The cursor bar follows azooKey's reflect style: the cursor stays fixed in
/// the middle while the surrounding text scrolls, arrows repeat after 0.4s,
/// and a horizontal swipe advances one character per accumulated distance.
private final class CursorBarView: UIView {
    private let palette: KeyboardPalette
    private let fontSize: CGFloat
    private let onMove: (Int) -> Void
    private var line: [String] = []
    private var displayLeftIndex = 0
    private var displayRightIndex = 0
    private var itemCount = 0
    private var itemWidth: CGFloat { fontSize * 1.3 }
    private var start = CGPoint.zero
    private var last = CGPoint.zero
    private var last2 = CGPoint.zero
    private var last3 = CGPoint.zero
    private var swipeCount = 0.0
    private var moving = false
    private var arrowOffset = 0
    private var arrowLongPressed = false
    private var arrowDownAt = 0.0
    private var longPressWorkItem: DispatchWorkItem?
    private var repeatTimer: Timer?
    private var autoDismissWorkItem: DispatchWorkItem?

    init(
        before: String,
        after: String,
        palette: KeyboardPalette,
        fontSize: CGFloat,
        onMove: @escaping (Int) -> Void
    ) {
        self.palette = palette
        self.fontSize = fontSize
        self.onMove = onMove
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        update(before: before, after: after)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 42) }

    func update(before: String, after: String) {
        let left = before.components(separatedBy: "\n").last ?? before
        line = Array(left + after).map { String($0) } + ["⏎"]
        updateItemCount()
        setNeedsDisplay()
    }

    func scheduleAutoDismiss(_ action: @escaping () -> Void) {
        autoDismissWorkItem?.cancel()
        let work = DispatchWorkItem(block: action)
        autoDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateItemCount()
    }

    private func updateItemCount() {
        guard bounds.width > 0 else { return }
        itemCount = max(0, (Int(bounds.width / itemWidth) >> 1) << 1)
        let half = itemCount / 2
        displayLeftIndex = line.count - half
        displayRightIndex = displayLeftIndex + itemCount
    }

    private func move(_ count: Int) {
        let center = displayLeftIndex + itemCount / 2
        guard center + count >= -1, line.count >= center + count else { return }
        displayLeftIndex += count
        displayRightIndex += count
        onMove(count)
        setNeedsDisplay()
    }

    private func tap(at x: CGFloat) {
        guard itemWidth > 0, bounds.width > 0 else { return }
        let offset = Int(((x - bounds.midX) / itemWidth).rounded(.toNearestOrAwayFromZero))
        move(offset)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let colors = [palette.key.cgColor, palette.background.cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: bounds.midX, y: bounds.midY), startRadius: 1, endCenter: CGPoint(x: bounds.midX, y: bounds.midY), endRadius: bounds.width / 2, options: [])
        } else {
            palette.key.setFill()
            context.fill(bounds)
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: palette.text.withAlphaComponent(0.4),
        ]
        let centerIndex = displayLeftIndex + itemCount / 2
        let startIndex = displayLeftIndex - 4
        for index in startIndex ..< displayRightIndex + 4 {
            guard line.indices.contains(index), !line[index].isEmpty else { continue }
            let value = line[index] as NSString
            let width = value.size(withAttributes: attributes).width
            let x = bounds.midX + CGFloat(index - centerIndex) * itemWidth - width / 2
            value.draw(at: CGPoint(x: x, y: bounds.midY - fontSize / 2 - 1), withAttributes: attributes)
        }
        let symbolAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: palette.text,
        ]
        ("‹‹" as NSString).draw(at: CGPoint(x: 12, y: bounds.midY - 11), withAttributes: symbolAttributes)
        ("››" as NSString).draw(at: CGPoint(x: bounds.width - 35, y: bounds.midY - 11), withAttributes: symbolAttributes)
        ("│" as NSString).draw(at: CGPoint(x: bounds.midX - 4, y: bounds.midY - (fontSize + 4) / 2 - 1), withAttributes: [
            .font: UIFont.boldSystemFont(ofSize: fontSize + 4),
            .foregroundColor: palette.text,
        ])
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let point = touches.first?.location(in: self) else { return }
        start = point
        last = point
        last2 = point
        last3 = point
        swipeCount = 0
        moving = false
        arrowLongPressed = false
        arrowDownAt = CACurrentMediaTime()
        arrowOffset = point.x < 48 ? -1 : (point.x > bounds.width - 48 ? 1 : 0)
        if arrowOffset != 0 {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.arrowOffset != 0 else { return }
                self.arrowLongPressed = true
                self.move(self.arrowOffset)
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                    guard let self, self.arrowLongPressed else { return }
                    self.move(self.arrowOffset)
                }
            }
            longPressWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let point = touches.first?.location(in: self) else { return }
        if hypot(point.x - start.x, point.y - start.y) > 20 {
            longPressWorkItem?.cancel()
            if arrowOffset == 0 { moving = true }
        }
        if arrowOffset == 0, moving {
            var direction = 0
            direction += point.x - last.x > 0 ? -1 : 1
            direction += last.x - last2.x > 0 ? -1 : 1
            direction += last2.x - last3.x > 0 ? -1 : 1
            if direction > 0, point.x < last3.x { swipeCount += Double(direction) / 3 * (last3.x - point.x) / 3 }
            else if direction < 0, point.x > last3.x { swipeCount -= Double(direction) / 3 * (last3.x - point.x) / 3 }
            while swipeCount >= 15 { move(1); swipeCount -= 15 }
            while swipeCount <= -15 { move(-1); swipeCount += 15 }
        }
        last3 = last2
        last2 = last
        last = point
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        longPressWorkItem?.cancel()
        repeatTimer?.invalidate()
        repeatTimer = nil
        guard let point = touches.first?.location(in: self) else { return }
        let elapsed = CACurrentMediaTime() - arrowDownAt
        if arrowOffset != 0 {
            if !arrowLongPressed, elapsed < 0.4, hypot(point.x - start.x, point.y - start.y) <= 20 { move(arrowOffset) }
        } else if !moving {
            tap(at: start.x)
        }
        arrowOffset = 0
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressWorkItem?.cancel()
        repeatTimer?.invalidate()
        repeatTimer = nil
        arrowOffset = 0
        super.touchesCancelled(touches, with: event)
    }
}

private final class RepeatDeleteButton: UIButton {
    private let press: () -> Void
    private var longPressWorkItem: DispatchWorkItem?
    private var repeatTimer: Timer?
    private var didLongPress = false

    init(action: @escaping () -> Void) {
        self.press = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        didLongPress = false
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.didLongPress = true
            self.press()
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in self?.press() }
            self.repeatTimer?.fire()
        }
        longPressWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressWorkItem?.cancel()
        repeatTimer?.invalidate()
        repeatTimer = nil
        super.touchesEnded(touches, with: event)
        if !didLongPress { press() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressWorkItem?.cancel()
        repeatTimer?.invalidate()
        repeatTimer = nil
        super.touchesCancelled(touches, with: event)
    }
}

private final class RepeatActionButton: UIButton {
    private let press: () -> Void
    private let longPress: () -> Void
    private var longPressWorkItem: DispatchWorkItem?
    private var repeatTimer: Timer?
    private var didLongPress = false

    init(action: @escaping () -> Void, longPress: @escaping () -> Void) {
        self.press = action
        self.longPress = longPress
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        didLongPress = false
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.didLongPress = true
            self.longPress()
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in self?.longPress() }
            self.repeatTimer?.fire()
        }
        longPressWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressWorkItem?.cancel()
        repeatTimer?.invalidate()
        repeatTimer = nil
        super.touchesEnded(touches, with: event)
        if !didLongPress { press() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressWorkItem?.cancel()
        repeatTimer?.invalidate()
        repeatTimer = nil
        super.touchesCancelled(touches, with: event)
    }
}

private final class FlickButton: UIButton {
    private let definition: FlickDefinition
    private let sensitivity: CGFloat
    private let callback: (String) -> Void
    private var start = CGPoint.zero
    private var longPressWorkItem: DispatchWorkItem?
    private var repeatTimer: Timer?
    private var didLongPress = false
    private var longPressFlicked = false
    private var cursorLongPressed = false
    private var cursorLongPressScheduled = false

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
        didLongPress = false
        longPressFlicked = false
        cursorLongPressed = false
        cursorLongPressScheduled = false
        guard definition.action == "delete" || definition.action == "space" else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.didLongPress = true
            if self.definition.action == "delete" {
                self.callback(self.definition.values[0])
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    self.callback(self.definition.values[0])
                }
                self.repeatTimer?.fire()
            } else {
                self.callback("__space_longpress__")
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in self?.callback("__space_longpress__") }
                self.repeatTimer?.fire()
            }
        }
        longPressWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        longPressWorkItem?.cancel()
        repeatTimer?.invalidate()
        repeatTimer = nil
        guard (!didLongPress || longPressFlicked) && !cursorLongPressed else { return }
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

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressWorkItem?.cancel()
        repeatTimer?.invalidate()
        repeatTimer = nil
        cursorLongPressScheduled = false
        super.touchesCancelled(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        let dx = point.x - start.x
        let dy = point.y - start.y
        if abs(dx) >= 20 * sensitivity || abs(dy) >= 20 * sensitivity {
            longPressWorkItem?.cancel()
            if didLongPress {
                longPressFlicked = true
                didLongPress = false
                repeatTimer?.invalidate()
                repeatTimer = nil
            }
            if definition.action == "space", abs(dx) > abs(dy), dx < 0, !cursorLongPressScheduled {
                cursorLongPressScheduled = true
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.cursorLongPressed = true
                    self.callback("__cursor_repeat__")
                    self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in self?.callback("__cursor_repeat__") }
                    self.repeatTimer?.fire()
                }
                longPressWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
            }
        }
        super.touchesMoved(touches, with: event)
    }
}

private class DirectionalKeyButton: UIButton {
    private var directionLabels: [String: UILabel] = [:]

    init(title: String, directionTitles: [String: String]) {
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        titleLabel?.numberOfLines = 2
        titleLabel?.textAlignment = .center
        for (direction, value) in directionTitles where !value.isEmpty {
            let label = UILabel()
            label.text = value
            label.textAlignment = .center
            label.numberOfLines = 1
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.65
            label.isUserInteractionEnabled = false
            label.accessibilityElementsHidden = true
            directionLabels[direction] = label
            addSubview(label)
        }
    }

    required init?(coder: NSCoder) { nil }

    func styleDirectionLabels(color: UIColor, fontSize: CGFloat) {
        for label in directionLabels.values {
            label.textColor = color
            label.font = .systemFont(ofSize: fontSize)
        }
    }

    override func titleRect(forContentRect contentRect: CGRect) -> CGRect {
        guard !directionLabels.isEmpty else { return super.titleRect(forContentRect: contentRect) }
        return CGRect(
            x: contentRect.width * 0.25,
            y: contentRect.height * 0.25,
            width: contentRect.width * 0.50,
            height: contentRect.height * 0.50
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let height = bounds.height
        directionLabels["left"]?.frame = CGRect(x: 0, y: height * 0.27, width: width * 0.35, height: height * 0.46)
        directionLabels["top"]?.frame = CGRect(x: width * 0.19, y: 0, width: width * 0.62, height: height * 0.34)
        directionLabels["right"]?.frame = CGRect(x: width * 0.65, y: height * 0.27, width: width * 0.35, height: height * 0.46)
        directionLabels["bottom"]?.frame = CGRect(x: width * 0.19, y: height * 0.66, width: width * 0.62, height: height * 0.34)
    }
}

private final class CustomFlickButton: DirectionalKeyButton {
    private let key: [String: Any]
    private let sensitivity: CGFloat
    private let callback: ([String: Any]?) -> Void
    private var start = CGPoint.zero
    private var longPressWorkItem: DispatchWorkItem?
    private var repeatTimer: Timer?
    private var didLongPress = false
    private var longPressFlicked = false

    init(
        key: [String: Any],
        directionTitles: [String: String],
        sensitivity: CGFloat,
        callback: @escaping ([String: Any]?) -> Void
    ) {
        self.key = key
        self.sensitivity = sensitivity
        self.callback = callback
        super.init(
            title: key["label"] as? String ?? key["name"] as? String ?? "",
            directionTitles: directionTitles
        )
    }

    required init?(coder: NSCoder) { nil }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        start = touches.first?.location(in: self) ?? .zero
        didLongPress = false
        longPressFlicked = false
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let action = key["longPress"] as? [String: Any]
            let repeated = key["longPressRepeat"] as? [String: Any]
            guard action != nil || repeated != nil else { return }
            didLongPress = true
            callback(action)
            if let repeated {
                repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
                    self?.callback(repeated)
                }
                repeatTimer?.fire()
            }
        }
        longPressWorkItem = work
        let duration = (key["duration"] as? String == "light") ? 0.125 : 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        longPressWorkItem?.cancel()
        repeatTimer?.invalidate()
        repeatTimer = nil
        guard !didLongPress || longPressFlicked else { return }
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

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        let dx = point.x - start.x
        let dy = point.y - start.y
        if abs(dx) >= 20 * sensitivity || abs(dy) >= 20 * sensitivity {
            longPressWorkItem?.cancel()
            if didLongPress {
                longPressFlicked = true
                didLongPress = false
                repeatTimer?.invalidate()
                repeatTimer = nil
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressWorkItem?.cancel()
        repeatTimer?.invalidate()
        repeatTimer = nil
        super.touchesCancelled(touches, with: event)
    }
}

private final class CustardLayoutView: UIView {
    private struct Item {
        let view: UIView
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    private let columns: Int
    private let rows: Int
    private let scrollDirection: String?
    private let crossCount: Int
    private let visibleCount: CGFloat
    private var items: [Item] = []
    private let scrollView = UIScrollView()
    private let contentView = UIView()

    init(columns: Int, rows: Int) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        self.scrollDirection = nil
        self.crossCount = 1
        self.visibleCount = 1
        super.init(frame: .zero)
    }

    init(scrollDirection: String, crossCount: Int, visibleCount: CGFloat) {
        self.columns = 1
        self.rows = 1
        self.scrollDirection = scrollDirection
        self.crossCount = max(1, crossCount)
        self.visibleCount = max(1, visibleCount)
        super.init(frame: .zero)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        addSubview(scrollView)
        scrollView.addSubview(contentView)
    }

    required init?(coder: NSCoder) { nil }

    func append(_ view: UIView, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        items.append(.init(view: view, x: x, y: y, width: width, height: height))
        addSubview(view)
    }

    func append(_ view: UIView) {
        items.append(.init(view: view, x: 0, y: 0, width: 1, height: 1))
        contentView.addSubview(view)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gap: CGFloat = 2
        guard let scrollDirection else {
            let cellWidth = bounds.width / CGFloat(columns)
            let cellHeight = bounds.height / CGFloat(rows)
            for item in items {
                item.view.frame = CGRect(
                    x: item.x * cellWidth + gap,
                    y: item.y * cellHeight + gap,
                    width: item.width * cellWidth - gap * 2,
                    height: item.height * cellHeight - gap * 2
                )
            }
            return
        }

        scrollView.frame = bounds
        if scrollDirection == "horizontal" {
            let cellHeight = bounds.height / CGFloat(crossCount)
            let cellWidth = bounds.width / visibleCount
            let columnCount = Int(ceil(Double(items.count) / Double(crossCount)))
            contentView.frame = CGRect(x: 0, y: 0, width: cellWidth * CGFloat(columnCount), height: bounds.height)
            for (index, item) in items.enumerated() {
                let column = index / crossCount
                let row = index % crossCount
                item.view.frame = CGRect(
                    x: CGFloat(column) * cellWidth + gap,
                    y: CGFloat(row) * cellHeight + gap,
                    width: cellWidth - gap * 2,
                    height: cellHeight - gap * 2
                )
            }
        } else {
            let cellWidth = bounds.width / CGFloat(crossCount)
            let cellHeight = bounds.height / visibleCount
            let rowCount = Int(ceil(Double(items.count) / Double(crossCount)))
            contentView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: cellHeight * CGFloat(rowCount))
            for (index, item) in items.enumerated() {
                let column = index % crossCount
                let row = index / crossCount
                item.view.frame = CGRect(
                    x: CGFloat(column) * cellWidth + gap,
                    y: CGFloat(row) * cellHeight + gap,
                    width: cellWidth - gap * 2,
                    height: cellHeight - gap * 2
                )
            }
        }
        scrollView.contentSize = contentView.bounds.size
    }
}

private final class CustardButton: DirectionalKeyButton {
    private let key: [String: Any]
    private let keyStyle: String
    private let variationsEnabled: Bool
    private let sensitivity: CGFloat
    private let callback: ([[String: Any]]) -> Void
    private var start = CGPoint.zero
    private var current = CGPoint.zero
    private var longPressWorkItem: DispatchWorkItem?
    private var repeatTimer: Timer?
    private var didLongPress = false
    private var repeatedLongPress = false
    private var longPressFlicked = false
    private var variationDidLongPress = false
    private var longPressDirection: String?

    init(
        title: String,
        directionTitles: [String: String],
        key: [String: Any],
        keyStyle: String,
        variationsEnabled: Bool,
        sensitivity: CGFloat,
        callback: @escaping ([[String: Any]]) -> Void
    ) {
        self.key = key
        self.keyStyle = keyStyle
        self.variationsEnabled = variationsEnabled
        self.sensitivity = sensitivity
        self.callback = callback
        super.init(title: title, directionTitles: directionTitles)
    }

    required init?(coder: NSCoder) { nil }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        start = touches.first?.location(in: self) ?? .zero
        current = start
        didLongPress = false
        repeatedLongPress = false
        longPressFlicked = false
        variationDidLongPress = false
        longPressDirection = nil
        let longPress = key["longpress_actions"] as? [String: Any] ?? [:]
        let startActions = longPress["start"] as? [[String: Any]] ?? []
        let repeated = longPress["repeat"] as? [[String: Any]] ?? []
        let handlesPCVariation = variationsEnabled && keyStyle == "pc_style" && !variations(type: "longpress_variation").isEmpty
        let handlesFlickLongPress = variationsEnabled && variations(type: "flick_variation").contains { variation in
            guard let variationKey = variation["key"] as? [String: Any],
                  let actions = variationKey["longpress_actions"] as? [String: Any] else { return false }
            return !(actions["start"] as? [[String: Any]] ?? []).isEmpty ||
                !(actions["repeat"] as? [[String: Any]] ?? []).isEmpty
        }
        guard !startActions.isEmpty || !repeated.isEmpty || handlesPCVariation || handlesFlickLongPress else { return }
        let delay = longPress["duration"] as? String == "light" ? 0.125 : 0.4
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let selected = self.selectedGestureKey(at: self.current)
            let selectedLongPress = selected["longpress_actions"] as? [String: Any] ?? [:]
            let selectedStart = selectedLongPress["start"] as? [[String: Any]] ?? []
            let selectedRepeat = selectedLongPress["repeat"] as? [[String: Any]] ?? []
            guard !selectedStart.isEmpty || !selectedRepeat.isEmpty || handlesPCVariation else { return }
            self.didLongPress = true
            self.variationDidLongPress = self.current.x != self.start.x || self.current.y != self.start.y
            self.repeatedLongPress = !selectedRepeat.isEmpty
            self.callback(selectedStart)
            if !selectedRepeat.isEmpty {
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
                    self?.callback(selectedRepeat)
                }
                self.repeatTimer?.fire()
            }
        }
        longPressWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        current = touches.first?.location(in: self) ?? current
        let dx = current.x - start.x
        let dy = current.y - start.y
        if abs(dx) >= 20 * sensitivity || abs(dy) >= 20 * sensitivity {
            longPressWorkItem?.cancel()
            if didLongPress {
                longPressFlicked = true
                didLongPress = false
                variationDidLongPress = false
                repeatTimer?.invalidate()
                repeatTimer = nil
            }
            let direction: String = abs(dx) > abs(dy) ? (dx < 0 ? "left" : "right") : (dy < 0 ? "top" : "bottom")
            if !didLongPress, direction != longPressDirection, variationsEnabled, keyStyle != "pc_style" {
                longPressDirection = direction
                let variation = variations(type: "flick_variation").first { $0["direction"] as? String == direction }
                let variationKey = variation?["key"] as? [String: Any] ?? [:]
                let variationLongPress = variationKey["longpress_actions"] as? [String: Any] ?? [:]
                let startActions = variationLongPress["start"] as? [[String: Any]] ?? []
                let repeatActions = variationLongPress["repeat"] as? [[String: Any]] ?? []
                if !startActions.isEmpty || !repeatActions.isEmpty {
                    let work = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        self.variationDidLongPress = true
                        self.didLongPress = true
                        self.repeatedLongPress = !repeatActions.isEmpty
                        self.callback(startActions)
                        if !repeatActions.isEmpty {
                            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in self?.callback(repeatActions) }
                            self.repeatTimer?.fire()
                        }
                    }
                    longPressWorkItem = work
                    let delay = variationLongPress["duration"] as? String == "light" ? 0.125 : 0.4
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                }
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        longPressWorkItem?.cancel()
        repeatTimer?.invalidate()
        repeatTimer = nil
        let end = touches.first?.location(in: self) ?? start
        current = end
        if didLongPress && !longPressFlicked {
            if variationDidLongPress { return }
            if variationsEnabled, keyStyle == "pc_style", !repeatedLongPress {
                let variations = variations(type: "longpress_variation")
                if !variations.isEmpty {
                    let index = Int((end.x / max(1, bounds.width)) * CGFloat(variations.count))
                    let selected = variations[min(max(0, index), variations.count - 1)]
                    let variationKey = selected["key"] as? [String: Any]
                    callback(variationKey?["press_actions"] as? [[String: Any]] ?? [])
                }
            }
            return
        }
        if longPressFlicked && variationDidLongPress { return }
        let selected = selectedGestureKey(at: end)
        callback(selected["press_actions"] as? [[String: Any]] ?? [])
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressWorkItem?.cancel()
        repeatTimer?.invalidate()
        repeatTimer = nil
        super.touchesCancelled(touches, with: event)
    }

    private func variations(type: String) -> [[String: Any]] {
        (key["variations"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == type }
    }

    private func selectedGestureKey(at point: CGPoint) -> [String: Any] {
        guard variationsEnabled, keyStyle != "pc_style" else { return key }
        let dx = point.x - start.x
        let dy = point.y - start.y
        let threshold = 20 * sensitivity
        let direction: String?
        if abs(dx) < threshold, abs(dy) < threshold {
            direction = nil
        } else if abs(dx) > abs(dy) {
            direction = dx < 0 ? "left" : "right"
        } else {
            direction = dy < 0 ? "top" : "bottom"
        }
        guard let direction,
              let variation = variations(type: "flick_variation").first(where: { $0["direction"] as? String == direction }),
              let variationKey = variation["key"] as? [String: Any] else { return key }
        return variationKey
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

private func katakanaToHiragana(_ value: String) -> String {
    String(value.unicodeScalars.map { scalar in
        if (0x30a1 ... 0x30f6).contains(scalar.value), let converted = UnicodeScalar(scalar.value - 0x60) {
            return Character(converted)
        }
        return Character(scalar)
    })
}

private let romanMap: [String: String] = [
    "kya": "きゃ", "kyu": "きゅ", "kyo": "きょ", "gya": "ぎゃ", "gyu": "ぎゅ", "gyo": "ぎょ", "sha": "しゃ", "shu": "しゅ", "sho": "しょ", "cha": "ちゃ", "chu": "ちゅ", "cho": "ちょ", "nya": "にゃ", "nyu": "にゅ", "nyo": "にょ", "hya": "ひゃ", "hyu": "ひゅ", "hyo": "ひょ", "mya": "みゃ", "myu": "みゅ", "myo": "みょ", "rya": "りゃ", "ryu": "りゅ", "ryo": "りょ", "fa": "ふぁ", "fi": "ふぃ", "fe": "ふぇ", "fo": "ふぉ", "shi": "し", "chi": "ち", "tsu": "つ",
    "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ", "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご", "sa": "さ", "si": "し", "su": "す", "se": "せ", "so": "そ", "za": "ざ", "zi": "じ", "ji": "じ", "zu": "ず", "ze": "ぜ", "zo": "ぞ", "ta": "た", "ti": "ち", "tu": "つ", "te": "て", "to": "と", "da": "だ", "di": "ぢ", "du": "づ", "de": "で", "do": "ど", "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の", "ha": "は", "hi": "ひ", "hu": "ふ", "fu": "ふ", "he": "へ", "ho": "ほ", "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ", "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ", "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も", "ya": "や", "yu": "ゆ", "yo": "よ", "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ", "wa": "わ", "wo": "を", "nn": "ん", "ltu": "っ", "xtu": "っ", "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お", "-": "ー", ",": "、", ".": "。",
]
