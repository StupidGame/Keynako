import UIKit
import AzooKeyConverterBridge

final class KeyboardViewController: UIInputViewController {
    private enum DictionaryMode { case closed, list, edit }

    private let backgroundImageView = KeyboardBackgroundImageView()
    private let rootStack = UIStackView()
    private let candidateScroll = UIScrollView()
    private let candidateStack = UIStackView()
    private let candidateExpandButton = UIButton(type: .system)
    private let candidatePanelScroll = UIScrollView()
    private let candidateGrid = UIStackView()
    private let keyboardStack = UIStackView()
    private let resizeHandle = UIButton(type: .system)
    private var horizontalKeyboardConstraints: [NSLayoutConstraint] = []
    private var heightConstraint: NSLayoutConstraint?
    private var candidatePanelHeightConstraint: NSLayoutConstraint?

    private var state: [String: Any] = [:]
    private var settings: [String: Any] = [:]
    private var palette = KeyboardPalette.light
    private var composing = ""
    private var rawRoman = ""
    private var lastDisplayed = ""
    private var candidates: [String] = []
    private var dictionaryMode: DictionaryMode = .closed
    private var dictionaryEditingId: Int?
    private var dictionaryImportance = 3
    private var dictionaryEnglishReading = false
    private var dictionaryDeleteArmed = false
    private weak var dictionaryReadingField: UITextField?
    private weak var dictionaryWordField: UITextField?
    private weak var dictionaryActiveField: UITextField?
    private var candidatePredictionReadings: [String: String] = [:]
    private var unknownPredictionTexts = Set<String>()
    private var candidateExpanded = false
    private var candidateBarShowsTabs = true
    private var selectedCandidateText: String?
    private var mode = "japanese"
    private var layout = "flick"
    private var inputTraitSignature: String?
    private var shift = false
    private var capsLock = false
    private var activeCustomTab: String?
    private var oneHandedMode = "full"
    private var oneHandedWidth: CGFloat = 0.78
    private var cursorBarVisible = false
    private weak var cursorBarView: CursorBarView?
    private var pendingQuickWordDelete: PendingQuickWordDelete?
    private var pendingReport: WrongConversionReport?
    private var osLexicon: [String: [String]] = [:]
    private var conversionDictionaryEntries: [AzooKeyHotfixDictionaryEntry] = []
    private var backgroundImageSignature: String?
    private var hasLoadedState = false
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
        applyOneHandedLayout()
        loadOSLexiconIfNeeded()
        renderCandidates()
        renderKeyboard()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        dictionaryMode = .closed
        reloadState()
        applyOneHandedLayout()
        loadOSLexiconIfNeeded()
        resetComposition()
        cursorBarVisible = false
        cursorBarView = nil
        synchronizeKeyboardWithInput(force: true)
        renderCandidates()
        renderKeyboard()
    }

    override func textWillChange(_ textInput: (any UITextInput)?) {
        super.textWillChange(textInput)
        reloadState()
        refreshCursorBar()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        synchronizeKeyboardWithInput(force: false)
    }

    private func configureView() {
        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        backgroundImageView.alpha = 0.85
        backgroundImageView.isUserInteractionEnabled = false
        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backgroundImageView)

        rootStack.axis = .vertical
        rootStack.spacing = 0
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootStack)
        NSLayoutConstraint.activate([
            backgroundImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundImageView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            rootStack.topAnchor.constraint(equalTo: view.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.setTitle("⋮", for: .normal)
        resizeHandle.titleLabel?.font = .systemFont(ofSize: 25)
        resizeHandle.accessibilityLabel = "片手モードの幅を調整"
        resizeHandle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragResizeHandle(_:))))
        view.addSubview(resizeHandle)

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
        let candidateHeader = UIStackView(arrangedSubviews: [candidateScroll, candidateExpandButton])
        candidateHeader.axis = .horizontal
        candidateHeader.spacing = 2
        candidateExpandButton.setTitle("⌄", for: .normal)
        candidateExpandButton.setTitleColor(palette.text, for: .normal)
        candidateExpandButton.backgroundColor = palette.key
        candidateExpandButton.layer.cornerRadius = 6
        candidateExpandButton.accessibilityLabel = "候補をさらに表示"
        candidateExpandButton.addTarget(self, action: #selector(toggleCandidatePanel), for: .touchUpInside)
        let expandWidth = candidateExpandButton.widthAnchor.constraint(equalToConstant: 42)
        expandWidth.priority = .defaultHigh
        expandWidth.isActive = true
        candidateExpandButton.isHidden = true
        rootStack.addArrangedSubview(candidateHeader)

        candidateGrid.axis = .vertical
        candidateGrid.spacing = 2
        candidateGrid.translatesAutoresizingMaskIntoConstraints = false
        candidatePanelScroll.addSubview(candidateGrid)
        candidatePanelHeightConstraint = candidatePanelScroll.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            candidateGrid.leadingAnchor.constraint(equalTo: candidatePanelScroll.contentLayoutGuide.leadingAnchor),
            candidateGrid.trailingAnchor.constraint(equalTo: candidatePanelScroll.contentLayoutGuide.trailingAnchor),
            candidateGrid.topAnchor.constraint(equalTo: candidatePanelScroll.contentLayoutGuide.topAnchor),
            candidateGrid.bottomAnchor.constraint(equalTo: candidatePanelScroll.contentLayoutGuide.bottomAnchor),
            candidateGrid.widthAnchor.constraint(equalTo: candidatePanelScroll.frameLayoutGuide.widthAnchor),
            candidatePanelHeightConstraint!,
        ])
        rootStack.addArrangedSubview(candidatePanelScroll)
        candidatePanelScroll.isHidden = true

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
        let savedMode = defaults.string(forKey: "keynako_one_handed_mode") ?? "full"
        oneHandedMode = ["left", "right"].contains(savedMode) ? savedMode : "full"
        let savedWidth = defaults.object(forKey: "keynako_one_handed_width") as? NSNumber
        oneHandedWidth = CGFloat(savedWidth?.doubleValue ?? 0.78).clamped(to: 0.6 ... 0.92)
        guard let value = defaults.string(forKey: "azookey_flutter_state"),
              let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if !hasLoadedState {
                state = [:]
                settings = [:]
                palette = traitCollection.userInterfaceStyle == .dark ? .dark : .light
            }
            applyKeyboardBackground()
            return
        }
        hasLoadedState = true
        state = object
        settings = object["settings"] as? [String: Any] ?? [:]
        reloadConversionDictionary()
        if settings["memory_reset_setting"] != nil,
           settings["memory_reset_setting"] as? Bool != false {
            conversionEngine?.resetLearning()
            settings["memory_reset_setting"] = false
            state["settings"] = settings
            saveState()
        }
        palette = loadPalette()
        applyKeyboardBackground()
        let scale = doubleSetting("keyboard_height_scale", fallback: 1).clamped(to: 0.7 ... 1.4)
        heightConstraint?.constant = 42 + 216 * scale
    }

    private func reloadConversionDictionary() {
        let storageKey = "keynako_hotfix_dictionary_storage"
        let tagKey = "keynako_hotfix_dictionary_storage_latest_sha"
        let tag = state[tagKey] as? String
            ?? state["azooKey_hotfix_dictionary_storage_latest_tag"] as? String
            ?? "none"
        let dictionary = state[storageKey] as? [String: Any]
            ?? state["azooKey_hotfix_dictionary_storage"] as? [String: Any]
        var entries: [AzooKeyHotfixDictionaryEntry] = []
        var hotfixVersion = "\(tag)|disabled"
        if let dictionary,
           let metadata = dictionary["metadata"] as? [String: Any],
           metadata["status"] as? String == "active",
           let values = dictionary["data"] as? [[String: Any]] {
            entries = values.compactMap { value -> AzooKeyHotfixDictionaryEntry? in
                guard let word = value["word"] as? String,
                      let ruby = value["ruby"] as? String,
                      let wordWeight = value["word_weight"] as? Double,
                      let lcid = value["lcid"] as? Int,
                      let rcid = value["rcid"] as? Int,
                      let mid = value["mid"] as? Int else { return nil }
                return AzooKeyHotfixDictionaryEntry(
                    word: word,
                    ruby: ruby,
                    wordWeight: wordWeight,
                    lcid: lcid,
                    rcid: rcid,
                    mid: mid
                )
            }
            let lastUpdate = metadata["last_update"] as? String ?? "unknown"
            hotfixVersion = "\(tag)|\(lastUpdate)|\(entries.count)"
        }
        var personalVersion = Hasher()
        for item in state["userDictionary"] as? [[String: Any]] ?? [] {
            guard item["isTemplateMode"] as? Bool != true,
                  let ruby = item["ruby"] as? String, !ruby.isEmpty,
                  let word = item["word"] as? String, !word.isEmpty else { continue }
            let importance = min(5, max(1, item["importance"] as? Int ?? 3))
            personalVersion.combine(ruby)
            personalVersion.combine(word)
            personalVersion.combine(importance)
            entries.append(AzooKeyHotfixDictionaryEntry(
                word: word,
                ruby: ruby,
                wordWeight: Double(importance - 3) * 2 - 9,
                lcid: 1285,
                rcid: 1285,
                mid: 501
            ))
        }
        conversionDictionaryEntries = entries
        conversionEngine?.updateHotfixDictionary(
            entries,
            version: "\(hotfixVersion)|personal:\(personalVersion.finalize())"
        )
    }

    private func loadPalette() -> KeyboardPalette {
        let dark = traitCollection.userInterfaceStyle == .dark
        let selectedKey = dark ? "darkThemeId" : "lightThemeId"
        let selected = state[selectedKey] as? String ?? (dark ? "midnight" : "classic")
        guard let themes = state["themes"] as? [[String: Any]],
              let theme = themes.first(where: { $0["id"] as? String == selected }) else {
            return dark ? .dark : .light
        }
        let backgroundImage = theme["backgroundImage"] as? String
        let backgroundImageRevision = (theme["backgroundImageRevision"] as? NSNumber)?.int64Value
        let keyOpacity: CGFloat = backgroundImage == nil
            ? 1
            : CGFloat(((theme["keyOpacity"] as? Double) ?? 0.72).clamped(to: 0.15 ... 1))
        return KeyboardPalette(
            background: color(theme["backgroundColor"], fallback: dark ? 0xff111827 : 0xffd1d5db),
            key: color(theme["keyColor"], fallback: dark ? 0xff374151 : 0xffffffff).withAlphaComponent(keyOpacity),
            special: color(theme["specialKeyColor"], fallback: dark ? 0xff1f2937 : 0xffadb5bd).withAlphaComponent(keyOpacity),
            text: color(theme["textColor"], fallback: dark ? 0xfff9fafb : 0xff111827),
            accent: color(theme["accentColor"], fallback: dark ? 0xff60a5fa : 0xff2563eb).withAlphaComponent(keyOpacity),
            backgroundImage: backgroundImage,
            backgroundImageRevision: backgroundImageRevision
        )
    }

    private func applyKeyboardBackground() {
        view.backgroundColor = palette.background
        let path = palette.backgroundImage
        var modificationDate: Date?
        if let path,
           let attributes = try? FileManager.default.attributesOfItem(atPath: path) {
            modificationDate = attributes[.modificationDate] as? Date
        }
        let signature: String?
        if let path, FileManager.default.fileExists(atPath: path) {
            let revision = palette.backgroundImageRevision.map { String($0) }
                ?? String(modificationDate?.timeIntervalSince1970 ?? 0)
            signature = "\(path):\(revision)"
        } else {
            signature = nil
        }
        if path == nil {
            backgroundImageView.image = nil
            backgroundImageSignature = nil
        } else if let signature,
                  (signature != backgroundImageSignature || backgroundImageView.image == nil),
                  let image = path.flatMap({ UIImage(contentsOfFile: $0) }) {
            backgroundImageView.image = image
            backgroundImageSignature = signature
        }
        // Keep the decoded image through a transient app-group file lookup
        // failure and reload it if UIKit recreated the view/image storage.
        let hasImage = path != nil && backgroundImageView.image != nil
        backgroundImageView.isHidden = !hasImage
        rootStack.backgroundColor = hasImage ? .clear : palette.background
        keyboardStack.backgroundColor = hasImage ? .clear : palette.background
    }

    private func renderKeyboard() {
        keyboardStack.removeAllArrangedSubviews()
        if let activeCustomTab {
            renderCustomTab(activeCustomTab)
        } else if mode == "symbols" {
            renderSymbols()
        } else if mode == "number", layout == "symbols" {
            renderSymbols()
        } else if mode == "number" {
            renderNumber()
        } else if mode == "phone" {
            renderPhone()
        } else if layout == "qwerty" {
            renderQwerty()
        } else {
            renderFlick()
        }
        if activeCustomTab == nil { renderStandaloneCustomKeys() }
    }

    private func renderFlick() {
        let spaceLabel = boolSetting("use_next_candidate_key", fallback: false)
            ? "次候補" : "空白"
        let pasteOnCursorKey = boolSetting("enable_paste_button_on_flick_cursorbar_key", fallback: false)
        let rows: [[FlickDefinition]]
        if mode == "english" {
            rows = [
                [.action("☆123", "symbols", target: "symbols_tab"), .init("@#/&_", ["@", "#", "/", "&", "_"]), .init("ABC", ["a", "b", "c", "2", ""]), .init("DEF", ["d", "e", "f", "3", ""]), .delete("⌫")],
                [.action("ABC", "english", target: "abc_tab"), .init("GHI", ["g", "h", "i", "4", ""]), .init("JKL", ["j", "k", "l", "5", ""]), .init("MNO", ["m", "n", "o", "6", ""]), .space(spaceLabel, pasteOnCursorKey: pasteOnCursorKey)],
                [.action("あいう", "japanese", target: "hira_tab"), .init("PQRS", ["p", "q", "r", "s", "7"]), .init("TUV", ["t", "u", "v", "8", ""]), .init("WXYZ", ["w", "x", "y", "z", "9"]), .action("改行", "enter")],
                [.action("🌐", "nextKeyboard"), .action("a/A", "upperLowerEnglish"), .init("'\"()", ["'", "\"", "(", ")", ""]), .init(".,?!", [".", ",", "?", "!", "'"], target: "kana_symbols"), .action("改行", "enter")],
            ]
        } else {
            rows = [
                [.action("☆123", "symbols", target: "symbols_tab"), .init("あ", ["あ", "い", "う", "え", "お"]), .init("か", ["か", "き", "く", "け", "こ"]), .init("さ", ["さ", "し", "す", "せ", "そ"]), .delete("⌫")],
                [.action("ABC", "english", target: "abc_tab"), .init("た", ["た", "ち", "つ", "て", "と"]), .init("な", ["な", "に", "ぬ", "ね", "の"]), .init("は", ["は", "ひ", "ふ", "へ", "ほ"]), .space(spaceLabel, pasteOnCursorKey: pasteOnCursorKey)],
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
        let english = mode == "english"
        let useShift = english && boolSetting("use_shift_key", fallback: false)
        let legacyShift: Bool
        if #available(iOS 18, *) {
            legacyShift = false
        } else {
            legacyShift = useShift && boolSetting("keep_deprecated_shift_key_behavior", fallback: true)
        }
        for (index, letters) in ["qwertyuiop", "asdfghjkl", "zxcvbnm"].enumerated() {
            let row = makeRow()
            if index == 1, legacyShift {
                row.addArrangedSubview(makeButton(capsLock ? "⇪" : "⇧", special: true, action: toggleShift))
            }
            for character in letters {
                let base = String(character)
                let label = shift || capsLock || textDocumentProxy.autocapitalizationType == .allCharacters
                    ? base.uppercased() : base
                row.addArrangedSubview(makeButton(label) { [weak self] in self?.input(label) })
            }
            if index == 2 {
                row.addArrangedSubview(
                    makeButton("⌫", special: true, quickWordDelete: true, action: delete)
                )
            } else if index == 1, english {
                if useShift {
                    row.addArrangedSubview(makeButton(".") { [weak self] in self?.input(".") })
                } else {
                    let aaKey = makeButton(capsLock ? "⇪" : "Aa", special: true) { [weak self] in
                        self?.pressAa()
                    }
                    aaKey.addGestureRecognizer(UILongPressGestureRecognizer(
                        target: self, action: #selector(toggleCapsLockFromAa(_:))
                    ))
                    row.addArrangedSubview(aaKey)
                }
            }
            keyboardStack.addArrangedSubview(row)
        }
        let bottom = makeRow()
        bottom.distribution = .fill
        bottom.addArrangedSubview(makeButton("☆123", special: true) { [weak self] in self?.setMode("symbols") })
        bottom.addArrangedSubview(makeButton("🌐", special: true, action: advanceToNextInputMode))
        if useShift && !legacyShift {
            bottom.addArrangedSubview(makeButton(capsLock ? "⇪" : "⇧", special: true, action: toggleShift))
        }
        let space = makeButton("space", action: self.space)
        bottom.addArrangedSubview(space)
        space.widthAnchor.constraint(equalTo: bottom.widthAnchor, multiplier: useShift && !legacyShift ? 0.35 : 0.42).isActive = true
        bottom.addArrangedSubview(makeButton("return", special: true, action: enter))
        keyboardStack.addArrangedSubview(bottom)
    }

    private func renderSymbols() {
        for values in defaultSymbolKeyboardRows {
            let row = makeRow()
            for value in values {
                let definition = FlickDefinition(
                    value.halfWidth,
                    [value.halfWidth, value.halfWidth, value.fullWidth, value.halfWidth, value.halfWidth]
                )
                let button = FlickButton(
                    definition: definition,
                    sensitivity: CGFloat(doubleSetting("flick_sensitivity_setting", fallback: 1))
                ) { [weak self] selected in
                    self?.directCommit(selected)
                    self?.feedback()
                }
                style(button, special: false)
                row.addArrangedSubview(button)
            }
            keyboardStack.addArrangedSubview(row)
        }
        let bottom = makeRow()
        bottom.addArrangedSubview(makeButton("あいう", special: true) { [weak self] in self?.setMode("japanese") })
        bottom.addArrangedSubview(makeButton("ABC", special: true) { [weak self] in self?.setMode("english") })
        bottom.addArrangedSubview(makeButton("space", action: space))
        bottom.addArrangedSubview(
            makeButton("⌫", special: true, quickWordDelete: true, action: delete)
        )
        bottom.addArrangedSubview(makeButton("return", special: true, action: enter))
        keyboardStack.addArrangedSubview(bottom)
    }

    private func renderNumber() {
        let keyboardType = textDocumentProxy.keyboardType ?? .default
        let showsSign = keyboardType == .numbersAndPunctuation
        let showsDecimal = keyboardType == .decimalPad || keyboardType == .numbersAndPunctuation
        renderNumericKeyboard(
            sideKeys: [
                NumericKey("⌫", action: "delete", special: true),
                showsSign ? NumericKey("-", input: "-") : NumericKey(),
                showsDecimal ? NumericKey(".", input: ".") : NumericKey(),
                NumericKey("改行", action: "enter", special: true),
            ],
            bottomLeft: NumericKey("ABC", action: "english", special: true)
        )
    }

    private func renderPhone() {
        renderNumericKeyboard(
            sideKeys: [
                NumericKey("⌫", action: "delete", special: true),
                NumericKey("+", input: "+"),
                NumericKey("#", input: "#"),
                NumericKey("改行", action: "enter", special: true),
            ],
            bottomLeft: NumericKey("*", input: "*")
        )
    }

    private func renderNumericKeyboard(sideKeys: [NumericKey], bottomLeft: NumericKey) {
        let rows = [
            [NumericKey("1", input: "1"), NumericKey("2", input: "2"), NumericKey("3", input: "3"), sideKeys[0]],
            [NumericKey("4", input: "4"), NumericKey("5", input: "5"), NumericKey("6", input: "6"), sideKeys[1]],
            [NumericKey("7", input: "7"), NumericKey("8", input: "8"), NumericKey("9", input: "9"), sideKeys[2]],
            [bottomLeft, NumericKey("0", input: "0"), NumericKey("☆123", action: "symbols", special: true), sideKeys[3]],
        ]
        for keys in rows {
            let row = makeRow()
            for key in keys {
                guard !key.label.isEmpty else {
                    row.addArrangedSubview(UIView())
                    continue
                }
                row.addArrangedSubview(makeButton(key.label, special: key.special) { [weak self] in
                    guard let self else { return }
                    switch key.action {
                    case "delete": self.delete()
                    case "enter": self.enter()
                    case "english": self.setMode("english")
                    case "symbols": self.setMode("symbols")
                    default: self.directCommit(key.input ?? "")
                    }
                })
            }
            keyboardStack.addArrangedSubview(row)
        }
    }

    private func synchronizeKeyboardWithInput(force: Bool) {
        let keyboardType = textDocumentProxy.keyboardType ?? .default
        let contentType = textDocumentProxy.textContentType?.rawValue ?? ""
        let capitalization = textDocumentProxy.autocapitalizationType ?? .sentences
        let signature = "\(keyboardType.rawValue)|\(contentType)|\(capitalization.rawValue)"
        guard force || signature != inputTraitSignature else { return }
        inputTraitSignature = signature

        let requestedMode: String
        if boolSetting("automatic_keyboard_switching", fallback: true) {
            requestedMode = requestedModeForCurrentInput(
                keyboardType: keyboardType,
                contentType: textDocumentProxy.textContentType,
                capitalization: capitalization
            )
        } else {
            requestedMode = "japanese"
        }

        if !force, requestedMode == mode { return }
        resetComposition()
        mode = requestedMode
        let selection = configuredKeyboardSelection(for: requestedMode)
        activeCustomTab = selection.customTab
        layout = selection.layout
        if !force {
            renderCandidates()
            renderKeyboard()
        }
    }

    private func requestedModeForCurrentInput(
        keyboardType: UIKeyboardType,
        contentType: UITextContentType?,
        capitalization: UITextAutocapitalizationType
    ) -> String {
        switch keyboardType {
        case .numberPad, .decimalPad, .asciiCapableNumberPad, .numbersAndPunctuation:
            return "number"
        case .phonePad, .namePhonePad:
            return "phone"
        case .asciiCapable, .emailAddress, .URL, .twitter, .webSearch:
            return "english"
        default:
            break
        }
        if capitalization == .allCharacters { return "english" }
        guard let contentType else { return "japanese" }
        switch contentType {
        case .emailAddress, .URL, .username, .password, .newPassword, .oneTimeCode:
            return "english"
        default:
            return "japanese"
        }
    }

    private func configuredKeyboardSelection(for requestedMode: String) -> (
        layout: String,
        customTab: String?
    ) {
        let key: String
        let fallback: String
        let allowed: Set<String>
        switch requestedMode {
        case "english":
            key = "keyboard_type_en"
            fallback = "flick"
            allowed = ["flick", "qwerty"]
        case "number":
            key = "keyboard_type_number"
            fallback = "tenkey"
            allowed = ["tenkey", "symbols"]
        case "phone":
            key = "keyboard_type_phone"
            fallback = "phone"
            allowed = ["phone"]
        case "datetime":
            key = "keyboard_type_datetime"
            fallback = "datetime"
            allowed = ["datetime"]
        default:
            key = "keyboard_type"
            fallback = "flick"
            allowed = ["flick", "qwerty"]
        }
        let configured = stringSetting(key, fallback: fallback)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if configured.hasPrefix("custom:") {
            let id = String(configured.dropFirst("custom:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty, customLayoutExists(id) {
                return (fallback, id)
            }
        }
        return (allowed.contains(configured) ? configured : fallback, nil)
    }

    private func customLayoutExists(_ id: String) -> Bool {
        if (state["customTabs"] as? [[String: Any]])?.contains(where: {
            ($0["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == id
        }) == true {
            return true
        }
        return (state["custards"] as? [[String: Any]])?.contains(where: {
            ($0["identifier"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == id
        }) == true
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
        bottom.addArrangedSubview(
            makeButton("⌫", special: true, quickWordDelete: true, action: delete)
        )
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
        let uppercaseLabels = keyStyle == "pc_style" && shouldUppercaseEnglishLabels
        let centerActions = key["press_actions"] as? [[String: Any]] ?? []
        let directionTitles = custardFlickDirectionLabels(
            key: key,
            label: label,
            variationsEnabled: variationsEnabled,
            uppercaseEnglish: uppercaseLabels
        )
        let button = CustardButton(
            title: directionTitles.isEmpty
                ? custardLabel(label, actions: centerActions, uppercaseEnglish: uppercaseLabels)
                : custardPrimaryLabel(label, actions: centerActions, uppercaseEnglish: uppercaseLabels),
            directionTitles: directionTitles,
            key: key,
            keyStyle: keyStyle,
            variationsEnabled: variationsEnabled,
            sensitivity: CGFloat(doubleSetting("flick_sensitivity_setting", fallback: 1)),
            makeCenterLongPressRollback: { [weak self] start, repeated in
                self?.makeCustardInputRollback(startActions: start, repeatActions: repeated)
            }
        ) { [weak self] actions, allowQuickWordDelete in
            self?.dispatch(actions, allowQuickWordDelete: allowQuickWordDelete)
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
            mode == "english" ? pressAa() : transformLastCharacter()
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
        selectedCandidateText = candidates[next]
        replaceDisplayed(with: candidates[next], commit: false)
        renderCandidates(showTabs: false, refreshCandidates: false)
    }

    private func custardLabel(
        _ label: [String: Any]?,
        actions: [[String: Any]] = [],
        uppercaseEnglish: Bool = false
    ) -> String {
        guard let label else { return "" }
        if let text = label["text"] as? String {
            return shiftedLabel(text, actions: actions, uppercaseEnglish: uppercaseEnglish)
        }
        if let image = label["system_image"] as? String { return systemImageLabel(image) }
        switch label["type"] as? String {
        case "main_and_sub":
            let main = shiftedLabel(
                label["main"] as? String ?? "",
                actions: actions,
                uppercaseEnglish: uppercaseEnglish
            )
            return "\(main)\n\(label["sub"] as? String ?? "")"
        case "main_and_directions":
            return shiftedLabel(
                label["main"] as? String ?? "",
                actions: actions,
                uppercaseEnglish: uppercaseEnglish
            )
        case "system_image": return systemImageLabel(label["system_image"] as? String ?? "")
        default: return label["text"] as? String ?? ""
        }
    }

    private func custardPrimaryLabel(
        _ label: [String: Any]?,
        actions: [[String: Any]] = [],
        uppercaseEnglish: Bool = false
    ) -> String {
        guard let label else { return "" }
        switch label["type"] as? String {
        case "main_and_sub", "main_and_directions":
            return shiftedLabel(
                label["main"] as? String ?? "",
                actions: actions,
                uppercaseEnglish: uppercaseEnglish
            )
        default:
            return custardLabel(label, actions: actions, uppercaseEnglish: uppercaseEnglish)
        }
    }

    private func custardFlickDirectionLabels(
        key: [String: Any],
        label: [String: Any]?,
        variationsEnabled: Bool,
        uppercaseEnglish: Bool
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
            let actions = variationKey?["press_actions"] as? [[String: Any]] ?? []
            let variationLabel = custardLabel(
                design?["label"] as? [String: Any],
                actions: actions,
                uppercaseEnglish: uppercaseEnglish
            )
            let actionLabel = actionDisplayLabel(
                actions.first,
                uppercaseEnglish: uppercaseEnglish,
                actionCount: actions.count
            )
            let declaredLabel = (declaredDirections?[direction] as? String).map {
                shiftedLabel($0, actions: actions, uppercaseEnglish: uppercaseEnglish)
            }
            let candidates: [String?] = [variationLabel, declaredLabel, actionLabel]
            if let value = candidates.compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                values[direction] = value
            }
        }
        return values
    }

    private func actionDisplayLabel(
        _ action: [String: Any]?,
        uppercaseEnglish: Bool = false,
        actionCount: Int = 1
    ) -> String? {
        guard let action else { return nil }
        let type = action["type"] as? String ?? "input"
        let value: String?
        switch type {
        case "input": value = action["text"] as? String ?? action["value"] as? String
        case "directInput": value = action["value"] as? String
        case "direct_input": value = action["text"] as? String
        default: value = nil
        }
        guard let value, !value.isEmpty else { return nil }
        return shiftedInputLabel(
            value,
            actionType: type,
            inputValue: value,
            actionCount: actionCount,
            uppercaseEnabled: uppercaseEnglish
        )
    }

    private func shiftedLabel(
        _ label: String,
        actions: [[String: Any]],
        uppercaseEnglish: Bool
    ) -> String {
        let action = actions.first
        let input = action?["text"] as? String ?? action?["value"] as? String
        return shiftedInputLabel(
            label,
            actionType: action?["type"] as? String ?? "",
            inputValue: input,
            actionCount: actions.count,
            uppercaseEnabled: uppercaseEnglish
        )
    }

    private func shiftedInputLabel(
        _ label: String,
        actionType: String,
        inputValue: String?,
        actionCount: Int,
        uppercaseEnabled: Bool
    ) -> String {
        guard uppercaseEnabled,
              label.count == 1,
              actionCount == 1,
              actionType == "input",
              inputValue == label else { return label }
        return label.uppercased()
    }

    private func systemImageLabel(_ name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmedName.lowercased() {
        case "delete.left", "delete.left.fill": return "⌫"
        case "delete.right", "delete.right.fill": return "⌦"
        case "xmark": return "×"
        case "globe", "globe.asia.australia", "globe.europe.africa": return "🌐"
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
        case "capslock", "capslock.fill": return "⇪"
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
        let uppercaseLabels = shouldUppercaseEnglishLabels
        let tapAction = key["tap"] as? [String: Any]
        let title = shiftedLabel(
            key["label"] as? String ?? key["name"] as? String ?? "",
            actions: tapAction.map { [$0] } ?? [],
            uppercaseEnglish: uppercaseLabels
        )
        let directionTitles = [
            "left": actionDisplayLabel(key["left"] as? [String: Any], uppercaseEnglish: uppercaseLabels),
            "top": actionDisplayLabel(key["up"] as? [String: Any], uppercaseEnglish: uppercaseLabels),
            "right": actionDisplayLabel(key["right"] as? [String: Any], uppercaseEnglish: uppercaseLabels),
            "bottom": actionDisplayLabel(key["down"] as? [String: Any], uppercaseEnglish: uppercaseLabels),
        ].compactMapValues { $0 }
        let button = CustomFlickButton(
            key: key,
            title: title,
            directionTitles: directionTitles,
            sensitivity: CGFloat(doubleSetting("flick_sensitivity_setting", fallback: 1))
        ) { [weak self] action, allowQuickWordDelete in
            self?.dispatch(action, allowQuickWordDelete: allowQuickWordDelete)
            self?.feedback()
        }
        style(button, special: false)
        return button
    }

    private func renderCandidates(showTabs: Bool? = nil, refreshCandidates: Bool = true) {
        if dictionaryMode != .closed { return }
        let tabsVisible = showTabs ?? (composing.isEmpty && rawRoman.isEmpty)
        if tabsVisible != candidateBarShowsTabs {
            candidateScroll.setContentOffset(.zero, animated: false)
        }
        candidateBarShowsTabs = tabsVisible
        candidateStack.removeAllArrangedSubviews()
        if showTabs == true {
            setCandidateExpanded(false)
            candidateExpandButton.isHidden = true
            cursorBarVisible = false
            cursorBarView = nil
        }
        if cursorBarVisible {
            setCandidateExpanded(false)
            candidateExpandButton.isHidden = true
            renderCursorBar()
            return
        }
        if tabsVisible {
            setCandidateExpanded(false)
            candidateExpandButton.isHidden = true
            if boolSetting("display_tab_bar_button", fallback: true) {
                renderTabBar()
            }
            return
        }
        if refreshCandidates { candidates = buildCandidates() }
        let dictionaryShortcut = makeCandidateButton("＋辞書") { [weak self] in
            guard let self else { return }
            let word = self.selectedCandidateText ?? self.candidates.first ?? ""
            self.showDictionaryEditor(reading: self.candidatePredictionReadings[word] ?? self.composing, word: word)
        }
        candidateStack.addArrangedSubview(dictionaryShortcut)
        // The expanded grid keeps the full list. The horizontal bar only
        // needs the leading results and the explicitly selected candidate.
        var visibleIndices = Array(candidates.indices.prefix(12))
        if let selectedCandidateText,
           let selectedIndex = candidates.firstIndex(of: selectedCandidateText),
           !visibleIndices.contains(selectedIndex) {
            visibleIndices.append(selectedIndex)
        }
        let visibleCandidateIndices = visibleIndices
        for index in visibleCandidateIndices {
            let candidate = candidates[index]
            let button = makeCandidateButton(candidate) { [weak self] in self?.commitCandidate(index) }
            button.longPressAction = { [weak self] in self?.showCandidatePreview(candidate, index: index) }
            button.setTitleColor(index == 0 ? palette.accent : palette.text, for: .normal)
            candidateStack.addArrangedSubview(button)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.dictionaryMode == .closed, !self.candidateBarShowsTabs,
                  self.candidateStack.arrangedSubviews.first === dictionaryShortcut,
                  !self.candidates.isEmpty else { return }
            let index = self.selectedCandidateText.flatMap { self.candidates.firstIndex(of: $0) } ?? 0
            guard let visibleIndex = visibleCandidateIndices.firstIndex(of: index),
                  self.candidateStack.arrangedSubviews.count > visibleIndex + 1 else { return }
            self.candidateScroll.layoutIfNeeded()
            let selectedView = self.candidateStack.arrangedSubviews[visibleIndex + 1]
            let frame = self.candidateStack.convert(selectedView.frame, to: self.candidateScroll)
            self.candidateScroll.scrollRectToVisible(frame, animated: false)
        }
        candidateExpandButton.isHidden = candidates.count <= 3
        candidateExpandButton.backgroundColor = palette.key
        candidateExpandButton.setTitleColor(palette.text, for: .normal)
        if candidates.count <= 3 { setCandidateExpanded(false) }
        if candidateExpanded { renderCandidateGrid() }
    }

    @objc private func toggleCandidatePanel() {
        setCandidateExpanded(!candidateExpanded)
        if candidateExpanded { renderCandidateGrid() }
    }

    private func setCandidateExpanded(_ expanded: Bool) {
        candidateExpanded = expanded
        candidatePanelScroll.isHidden = !expanded
        candidatePanelHeightConstraint?.constant = expanded ? 176 : 0
        heightConstraint?.constant = expanded ? 434 : 258
        candidateExpandButton.setTitle(expanded ? "⌃" : "⌄", for: .normal)
        candidateExpandButton.accessibilityLabel = expanded ? "候補を閉じる" : "候補をさらに表示"
    }

    private func renderCandidateGrid() {
        candidateGrid.removeAllArrangedSubviews()
        for start in stride(from: 0, to: candidates.count, by: 3) {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 2
            row.heightAnchor.constraint(equalToConstant: 42).isActive = true
            for index in start ..< min(start + 3, candidates.count) {
                let candidate = candidates[index]
                let button = makeCandidateButton(candidate) { [weak self] in self?.commitCandidate(index) }
                button.longPressAction = { [weak self] in
                    self?.showCandidatePreview(candidate, index: index)
                }
                button.setTitleColor(index == 0 ? palette.accent : palette.text, for: .normal)
                row.addArrangedSubview(button)
            }
            for _ in row.arrangedSubviews.count ..< 3 { row.addArrangedSubview(UIView()) }
            candidateGrid.addArrangedSubview(row)
        }
    }

    private func toggleCursorBar() {
        cursorBarVisible.toggle()
        if cursorBarVisible {
            setCandidateExpanded(false)
            candidateExpandButton.isHidden = true
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
            reflectStyle: boolSetting("use_move_cursor_bar_beta", fallback: true),
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
        candidateStack.addArrangedSubview(makeTabButton("辞書", action: showDictionaryList))
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
            candidateStack.addArrangedSubview(makeTabButton(title) { [weak self] in self?.selectTab(value) })
        }
        if boolSetting("enable_clipboard_history_manager_tab", fallback: false), !values.contains("clipboard") {
            candidateStack.addArrangedSubview(makeTabButton("📋", action: showClipboardHistory))
        }
    }

    private func showDictionaryList() {
        dictionaryMode = .list
        dictionaryReadingField = nil
        dictionaryWordField = nil
        dictionaryActiveField = nil
        dictionaryDeleteArmed = false
        cursorBarVisible = false
        candidateStack.removeAllArrangedSubviews()
        candidateScroll.setContentOffset(.zero, animated: false)
        candidateStack.addArrangedSubview(makeCandidateButton("＋単語") { [weak self] in self?.showDictionaryEditor() })
        candidateStack.addArrangedSubview(makeCandidateButton("辞書を閉じる", action: closeDictionaryEditor))
        candidateGrid.removeAllArrangedSubviews()
        candidatePanelScroll.setContentOffset(.zero, animated: false)
        let entries = state["userDictionary"] as? [[String: Any]] ?? []
        for entry in entries where entry["isTemplateMode"] as? Bool != true {
            guard let ruby = entry["ruby"] as? String, !ruby.isEmpty,
                  let word = entry["word"] as? String, !word.isEmpty else { continue }
            let id = (entry["id"] as? NSNumber)?.intValue
            let importance = (entry["importance"] as? NSNumber)?.intValue ?? 3
            let button = makeCandidateButton("\(ruby) → \(word)　重要度 \(importance)") { [weak self] in
                self?.showDictionaryEditor(reading: ruby, word: word, id: id, importance: importance)
            }
            button.contentHorizontalAlignment = .left
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.accessibilityLabel = "\(ruby) → \(word)　重要度 \(importance)"
            button.heightAnchor.constraint(equalToConstant: 42).isActive = true
            candidateGrid.addArrangedSubview(button)
        }
        if candidateGrid.arrangedSubviews.isEmpty {
            let label = UILabel()
            label.text = "登録した単語はまだないよ。＋単語から追加できる"
            label.textColor = palette.text
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 13)
            candidateGrid.addArrangedSubview(label)
        }
        candidateExpandButton.isHidden = true
        setCandidateExpanded(true)
    }

    private func showDictionaryEditor(
        reading: String = "", word: String = "", id: Int? = nil, importance: Int = 3
    ) {
        dictionaryMode = .edit
        dictionaryEditingId = id
        dictionaryImportance = min(5, max(1, importance))
        dictionaryEnglishReading = mode == "english" || (id != nil && reading.unicodeScalars.allSatisfy { $0.isASCII })
        dictionaryDeleteArmed = false
        candidateGrid.removeAllArrangedSubviews()
        candidatePanelScroll.setContentOffset(.zero, animated: false)
        func field(_ label: String, _ value: String) -> UITextField {
            let view = UITextField()
            view.placeholder = label
            view.text = value
            view.textColor = palette.text
            view.backgroundColor = palette.key
            view.borderStyle = .roundedRect
            view.inputView = UIView(frame: .zero)
            view.addTarget(self, action: #selector(dictionaryFieldDidBegin(_:)), for: .editingDidBegin)
            view.heightAnchor.constraint(equalToConstant: 44).isActive = true
            candidateGrid.addArrangedSubview(view)
            return view
        }
        dictionaryReadingField = field("読み（ローマ字も入力できる）", reading)
        dictionaryWordField = field("単語", word)
        dictionaryActiveField = reading.isEmpty ? dictionaryReadingField : dictionaryWordField
        let hint = UILabel()
        hint.text = "欄を選んで編集。漢字は候補から登録するか貼り付けできる"
        hint.textColor = palette.text
        hint.font = .systemFont(ofSize: 12)
        hint.numberOfLines = 2
        candidateGrid.addArrangedSubview(hint)
        candidateExpandButton.isHidden = true
        setCandidateExpanded(true)
        renderDictionaryEditorActions()
    }

    @objc private func dictionaryFieldDidBegin(_ field: UITextField) {
        dictionaryActiveField = field
    }

    private func renderDictionaryEditorActions() {
        candidateStack.removeAllArrangedSubviews()
        candidateScroll.setContentOffset(.zero, animated: false)
        candidateStack.addArrangedSubview(makeCandidateButton("保存", action: saveDictionaryEntry))
        candidateStack.addArrangedSubview(makeCandidateButton("戻る", action: showDictionaryList))
        if dictionaryEditingId != nil {
            candidateStack.addArrangedSubview(makeCandidateButton(dictionaryDeleteArmed ? "削除する" : "削除") { [weak self] in
                guard let self else { return }
                if self.dictionaryDeleteArmed { self.deleteDictionaryEntry() } else {
                    self.dictionaryDeleteArmed = true
                    self.renderDictionaryEditorActions()
                }
            })
        }
        candidateStack.addArrangedSubview(makeCandidateButton("貼付") { [weak self] in
            guard let self, self.hasFullAccess, let value = UIPasteboard.general.string else { return }
            self.editDictionaryText(value)
        })
        candidateStack.addArrangedSubview(makeCandidateButton(dictionaryEnglishReading ? "英語の読み" : "日本語の読み") { [weak self] in
            guard let self else { return }
            self.dictionaryEnglishReading.toggle()
            self.renderDictionaryEditorActions()
        })
        candidateStack.addArrangedSubview(makeCandidateButton("重要度 \(dictionaryImportance)") { [weak self] in
            guard let self else { return }
            self.dictionaryImportance = self.dictionaryImportance % 5 + 1
            self.renderDictionaryEditorActions()
        })
    }

    private func saveDictionaryEntry() {
        let rawReading = dictionaryReadingField?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let word = dictionaryWordField?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ruby = dictionaryEnglishReading
            ? rawReading.lowercased()
            : katakanaToHiragana(romanToHiragana(rawReading.lowercased()))
        guard !ruby.isEmpty, !word.isEmpty, ruby.count <= 128, word.count <= 128,
              !ruby.contains("\t"), !word.contains("\t"),
              !ruby.contains("\n"), !word.contains("\n") else {
            renderDictionaryEditorActions()
            candidateStack.addArrangedSubview(makeCandidateButton("読みと単語を確認してね", action: {}))
            return
        }
        var entries = state["userDictionary"] as? [[String: Any]] ?? []
        let nextId = (entries.compactMap { ($0["id"] as? NSNumber)?.intValue }.max() ?? -1) + 1
        let editedIndex = dictionaryEditingId.flatMap { id in
            entries.firstIndex { ($0["id"] as? NSNumber)?.intValue == id }
        }
        let duplicateIndex = entries.firstIndex {
            ($0["isTemplateMode"] as? Bool) != true &&
                ($0["ruby"] as? String) == ruby && ($0["word"] as? String) == word
        }
        if let editedIndex, let duplicateIndex, editedIndex != duplicateIndex {
            renderDictionaryEditorActions()
            candidateStack.addArrangedSubview(makeCandidateButton("同じ読みと単語が登録済みだよ", action: {}))
            return
        }
        let index = editedIndex ?? duplicateIndex
        var entry = index.map { entries[$0] } ?? [:]
        entry["id"] = (entry["id"] as? NSNumber)?.intValue ?? nextId
        entry["ruby"] = ruby
        entry["word"] = word
        entry["importance"] = dictionaryImportance
        entry["shared"] = false
        entry["isTemplateMode"] = false
        if let index { entries[index] = entry } else { entries.append(entry) }
        state["userDictionary"] = entries
        saveState()
        reloadConversionDictionary()
        showDictionaryList()
    }

    private func deleteDictionaryEntry() {
        guard let id = dictionaryEditingId else { return }
        var entries = state["userDictionary"] as? [[String: Any]] ?? []
        entries.removeAll { ($0["id"] as? NSNumber)?.intValue == id }
        state["userDictionary"] = entries
        saveState()
        reloadConversionDictionary()
        showDictionaryList()
    }

    private func closeDictionaryEditor() {
        dictionaryMode = .closed
        dictionaryReadingField = nil
        dictionaryWordField = nil
        dictionaryActiveField = nil
        setCandidateExpanded(false)
        renderCandidates()
    }

    private func editDictionaryText(_ value: String) {
        guard let field = dictionaryActiveField,
              !value.contains("\n"), !value.contains("\r") else { return }
        let selection = field.selectedTextRange
        let selectedCount = selection.flatMap { field.text(in: $0)?.count } ?? 0
        guard (field.text?.count ?? 0) - selectedCount + value.count <= 128 else { return }
        if let selection {
            field.replace(selection, withText: value)
        } else {
            field.text = (field.text ?? "") + value
        }
    }

    private func deleteDictionaryText() {
        guard let field = dictionaryActiveField else { return }
        if field.selectedTextRange != nil {
            field.deleteBackward()
        } else {
            field.text = String((field.text ?? "").dropLast())
        }
    }

    private func selectTab(_ value: String) {
        if dictionaryMode == .edit && !["dismiss", "japanese", "english"].contains(value) { return }
        if dictionaryMode == .list { closeDictionaryEditor() }
        switch value {
        case "dismiss": dismissKeyboard()
        case "emoji": showEmoji()
        case "japanese": setMode("japanese")
        case "english": setMode("english")
        case "clipboard": showClipboardHistory()
        case "resize":
            if oneHandedMode == "full" { showResizeControls() }
            else { setOneHandedMode("full") }
        default:
            if value.hasPrefix("custom:") {
                switchToCustomLayout(String(value.dropFirst(7)))
            }
        }
    }

    private func showResizeControls() {
        candidateStack.removeAllArrangedSubviews()
        candidateStack.addArrangedSubview(makeCandidateButton(oneHandedMode == "left" ? "✓ 左寄せ" : "← 左寄せ") { [weak self] in self?.setOneHandedMode("left") })
        if oneHandedMode == "full" || !boolSetting("hide_reset_button_in_one_handed_mode", fallback: false) {
            candidateStack.addArrangedSubview(makeCandidateButton(oneHandedMode == "full" ? "✓ 標準" : "↔ 標準") { [weak self] in self?.setOneHandedMode("full") })
        }
        candidateStack.addArrangedSubview(makeCandidateButton(oneHandedMode == "right" ? "✓ 右寄せ" : "右寄せ →") { [weak self] in self?.setOneHandedMode("right") })
        candidateStack.addArrangedSubview(makeCandidateButton("閉じる") { [weak self] in self?.renderCandidates() })
    }

    private func setOneHandedMode(_ mode: String) {
        oneHandedMode = mode
        UserDefaults(suiteName: "group.com.azooKey.keyboard")?.set(mode, forKey: "keynako_one_handed_mode")
        applyOneHandedLayout()
        if mode == "full" { renderCandidates() }
        else { showResizeControls() }
    }

    private func applyOneHandedLayout() {
        NSLayoutConstraint.deactivate(horizontalKeyboardConstraints)
        let width = rootStack.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: oneHandedMode == "full" ? 1 : oneHandedWidth)
        let position: NSLayoutConstraint
        if oneHandedMode == "right" {
            position = rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        } else {
            position = rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        }
        horizontalKeyboardConstraints = [width, position]
        if oneHandedMode != "full" {
            let handleEdge = oneHandedMode == "right"
                ? resizeHandle.leadingAnchor.constraint(equalTo: rootStack.leadingAnchor)
                : resizeHandle.trailingAnchor.constraint(equalTo: rootStack.trailingAnchor)
            horizontalKeyboardConstraints += [
                handleEdge,
                resizeHandle.centerYAnchor.constraint(equalTo: rootStack.centerYAnchor),
                resizeHandle.widthAnchor.constraint(equalToConstant: 22),
                resizeHandle.heightAnchor.constraint(equalToConstant: 64),
            ]
        }
        NSLayoutConstraint.activate(horizontalKeyboardConstraints)
        resizeHandle.isHidden = oneHandedMode == "full"
        resizeHandle.backgroundColor = palette.special
        resizeHandle.setTitleColor(palette.text, for: .normal)
        resizeHandle.layer.cornerRadius = 8
    }

    @objc private func dragResizeHandle(_ recognizer: UIPanGestureRecognizer) {
        guard oneHandedMode != "full", recognizer.state == .changed || recognizer.state == .ended,
              view.bounds.width > 0 else { return }
        let x = recognizer.location(in: view).x
        oneHandedWidth = ((oneHandedMode == "right" ? view.bounds.width - x : x) / view.bounds.width)
            .clamped(to: 0.6 ... 0.92)
        applyOneHandedLayout()
        if recognizer.state == .ended {
            UserDefaults(suiteName: "group.com.azooKey.keyboard")?.set(Double(oneHandedWidth), forKey: "keynako_one_handed_width")
        }
    }

    private func input(_ value: String) {
        if dictionaryMode == .edit { editDictionaryText(value); return }
        if !value.isEmpty,
           value.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains) {
            directCommit(value)
            return
        }
        if closingDelimiter(for: value) != nil {
            directCommit(value)
            return
        }
        if mode == "english" {
            inputEnglishText(punctuationForInputMode(value, mode: mode))
            return
        }
        let value = punctuationForInputMode(value, mode: mode)
        if layout == "qwerty" {
            rawRoman += value.lowercased()
            composing = romanToHiragana(rawRoman)
        } else {
            composing += value
        }
        updateComposition()
    }

    private func inputEnglishText(_ value: String) {
        if dictionaryMode == .edit { editDictionaryText(value); return }
        let allCapsInput = textDocumentProxy.autocapitalizationType == .allCharacters
        let resolved = shift || capsLock || allCapsInput ? value.uppercased() : value
        let isWordInput = !resolved.isEmpty && resolved.unicodeScalars.allSatisfy {
            (0x41 ... 0x5a).contains($0.value) || (0x61 ... 0x7a).contains($0.value)
        }
        if allCapsInput {
            // A host can commit uppercase text as soon as it arrives. Avoid
            // rewriting that text as an active composition on the next key.
            directCommit(resolved)
        } else if isWordInput || canContinueEmailComposition(resolved) {
            composing += resolved
            updateComposition()
        } else {
            directCommit(resolved)
        }
        if shift, !capsLock {
            shift = false
            renderKeyboard()
        }
    }

    private func updateComposition() {
        selectedCandidateText = nil
        candidates = buildCandidates()
        if completeStableFirstClauseIfNeeded() { return }
        let displayed: String
        if mode == "english" {
            displayed = composing
        } else if boolSetting("live_conversion", fallback: true) {
            displayed = candidates.first(where: { candidatePredictionReadings[$0] == nil }) ?? composing
        } else {
            displayed = composing
        }
        replaceDisplayed(with: displayed, commit: false)
        renderCandidates(showTabs: false, refreshCandidates: false)
    }

    private func completeStableFirstClauseIfNeeded() -> Bool {
        guard mode == "japanese", boolSetting("live_conversion", fallback: true),
              let clause = conversionEngine?.completedClause,
              composing.hasPrefix(clause.reading),
              composing.count > clause.reading.count,
              let first = candidates.first(where: { candidatePredictionReadings[$0] == nil }),
              first.hasPrefix(clause.text) else { return false }
        let remaining = String(composing.dropFirst(clause.reading.count))
        var remainingRoman = ""
        if layout == "qwerty" {
            guard let split = rawRoman.indices.first(where: { index in
                romanToHiragana(String(rawRoman[..<index])) == clause.reading &&
                    romanToHiragana(String(rawRoman[index...])) == remaining
            }) else { return false }
            remainingRoman = String(rawRoman[split...])
        }
        replaceDisplayed(with: clause.text, commit: true)
        conversionEngine?.commit(candidateText: clause.text, learningMode: effectiveLearningMode())
        composing = remaining
        rawRoman = remainingRoman
        updateComposition()
        return true
    }

    private func replaceDisplayed(with value: String, commit: Bool) {
        if stringSetting("marked_text_setting_beta", fallback: "disabled") != "disabled" {
            textDocumentProxy.setMarkedText(value, selectedRange: NSRange(location: value.utf16.count, length: 0))
            if commit { textDocumentProxy.unmarkText() }
        } else {
            // Clear an actual host selection before replacing our displayed
            // composition. An empty insert on every key can disturb editors
            // that transform or immediately commit the inserted text.
            if textDocumentProxy.selectedText?.isEmpty == false {
                textDocumentProxy.insertText("")
            }
            for _ in lastDisplayed { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(value)
        }
        lastDisplayed = commit ? "" : value
    }

    private func commitCandidate(_ index: Int) {
        guard candidates.indices.contains(index) else { return }
        let selected = candidates[index]
        let report = makeReport(selected: selected, index: index)
        let englishInput = mode == "english" ? composing : nil
        replaceDisplayed(with: selected, commit: true)
        learnCandidate(input: composing, candidate: selected, english: englishInput != nil, explicitSelection: true)
        if englishInput == nil {
            conversionEngine?.commit(
                candidateText: selected,
                learningMode: effectiveLearningMode()
            )
        }
        resetComposition()
        renderCandidates()
        if englishInput == nil { maybeOfferReport(report) }
    }

    private func commitComposition(useCandidate: Bool = true) {
        guard !composing.isEmpty || !rawRoman.isEmpty else { return }
        let explicitSelection = selectedCandidateText != nil
        let available = candidates.isEmpty ? buildCandidates() : candidates
        let selected = useCandidate
            ? (selectedCandidateText ?? available.first(where: { candidatePredictionReadings[$0] == nil }) ?? composing)
            : composing
        let englishInput = mode == "english" ? composing : nil
        replaceDisplayed(with: selected, commit: true)
        if useCandidate {
            learnCandidate(input: composing, candidate: selected, english: englishInput != nil, explicitSelection: explicitSelection)
        }
        if useCandidate, englishInput == nil {
            conversionEngine?.commit(
                candidateText: selected,
                learningMode: effectiveLearningMode()
            )
        }
        resetComposition()
        renderCandidates()
    }

    private func directCommit(_ value: String, normalizePunctuation: Bool = true) {
        if dictionaryMode == .edit {
            if value.contains("\n") { saveDictionaryEntry() } else { editDictionaryText(value) }
            return
        }
        commitComposition()
        let input = normalizePunctuation ? punctuationForInputMode(value, mode: mode) : value
        if let closingDelimiter = closingDelimiter(for: input) {
            textDocumentProxy.insertText(input + closingDelimiter)
            textDocumentProxy.adjustTextPosition(byCharacterOffset: -1)
        } else {
            textDocumentProxy.insertText(input)
        }
        candidates = []
        renderCandidates()
        refreshCursorBar()
    }

    private func delete() {
        if dictionaryMode == .edit { deleteDictionaryText(); return }
        if deleteSelectedText() { return }
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

    private func deleteSelectedText() -> Bool {
        guard let selected = textDocumentProxy.selectedText, !selected.isEmpty else { return false }
        textDocumentProxy.insertText("")
        pendingQuickWordDelete = nil
        resetComposition()
        renderCandidates()
        refreshCursorBar()
        return true
    }

    /// The first press remains immediate. A second quick press completes the
    /// one word that was under the cursor before that first character moved.
    private func quickDelete() {
        if dictionaryMode == .edit { deleteDictionaryText(); return }
        if deleteSelectedText() { return }
        let now = CACurrentMediaTime()
        let intervalMilliseconds = min(1000, max(100,
            intSetting("quick_word_delete_interval_ms", fallback: 350)))
        let interval = Double(intervalMilliseconds) / 1000
        if let pending = pendingQuickWordDelete, now <= pending.deadline {
            let applied: Bool
            if pending.composition {
                if composing == pending.expectedComposing,
                   rawRoman == pending.expectedRawRoman {
                    composing = pending.targetComposing
                    rawRoman = pending.targetRawRoman
                    if composing.isEmpty, rawRoman.isEmpty {
                        replaceDisplayed(with: "", commit: true)
                        resetComposition()
                        renderCandidates()
                    } else {
                        updateComposition()
                    }
                    applied = true
                } else {
                    applied = false
                }
            } else if (textDocumentProxy.documentContextBeforeInput ?? "") == pending.expectedContext {
                for _ in 0 ..< pending.remainingContextCount {
                    textDocumentProxy.deleteBackward()
                }
                refreshCursorBar()
                applied = true
            } else {
                applied = false
            }
            pendingQuickWordDelete = nil
            if applied { return }
        } else {
            pendingQuickWordDelete = nil
        }

        if !composing.isEmpty || !rawRoman.isEmpty {
            let originalComposing = composing
            let count = backwardWordDeleteCount(in: originalComposing)
            guard count > 0 else { return }
            let targetComposing = String(originalComposing.dropLast(min(count, originalComposing.count)))
            let targetRawRoman = rawRoman.isEmpty
                ? ""
                : (rawRomanPrefix(forComposition: targetComposing) ?? "")
            delete()
            pendingQuickWordDelete = PendingQuickWordDelete(
                deadline: now + interval,
                composition: true,
                expectedComposing: composing,
                expectedRawRoman: rawRoman,
                targetComposing: targetComposing,
                targetRawRoman: targetRawRoman
            )
            return
        }

        let originalContext = textDocumentProxy.documentContextBeforeInput ?? ""
        guard !originalContext.isEmpty else {
            // Some host applications do not expose document context to a
            // keyboard extension. Keep ordinary Backspace working there even
            // though a word boundary cannot be calculated.
            delete()
            return
        }
        let count = backwardWordDeleteCount(in: originalContext)
        delete()
        pendingQuickWordDelete = PendingQuickWordDelete(
            deadline: now + interval,
            composition: false,
            expectedContext: String(originalContext.dropLast()),
            remainingContextCount: max(0, count - 1)
        )
    }

    private func deleteForward() {
        if dictionaryMode == .edit { deleteDictionaryText(); return }
        if deleteSelectedText() { return }
        guard composing.isEmpty, rawRoman.isEmpty,
              !(textDocumentProxy.documentContextAfterInput ?? "").isEmpty else { return }
        textDocumentProxy.adjustTextPosition(byCharacterOffset: 1)
        textDocumentProxy.deleteBackward()
        refreshCursorBar()
    }

    private func space() {
        if dictionaryMode == .edit { editDictionaryText(" "); return }
        if composing.isEmpty, rawRoman.isEmpty {
            directCommit(" ")
        } else if layout == "flick", boolSetting("use_next_candidate_key", fallback: false), candidates.count > 1 {
            selectNextCandidate()
        } else if mode == "english" {
            commitComposition()
            directCommit(" ")
        } else {
            commitComposition()
        }
    }

    private func spaceWithoutConversion() {
        if dictionaryMode == .edit { editDictionaryText(" "); return }
        commitComposition(useCandidate: false)
        directCommit(" ")
        refreshCursorBar()
    }

    private func enter() {
        if dictionaryMode == .edit { saveDictionaryEntry(); return }
        commitComposition()
        textDocumentProxy.insertText("\n")
    }

    private func toggleShift() {
        if shift { capsLock.toggle() }
        shift = !shift || capsLock
        renderKeyboard()
    }

    private func pressAa() {
        if capsLock {
            capsLock = false
            shift = false
            renderKeyboard()
        } else {
            transformLastCharacter()
        }
    }

    @objc private func toggleCapsLockFromAa(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }
        capsLock.toggle()
        shift = capsLock
        renderKeyboard()
    }

    private func setMode(_ newMode: String) {
        if dictionaryMode != .edit, mode != "english" || newMode != "english" { commitComposition() }
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
        if definition.action == "upperLowerEnglish", value == "__capslock__" {
            capsLock.toggle()
            shift = capsLock
            renderKeyboard()
            return
        }
        if definition.action == "space", value == "__space_longpress__" {
            if candidates.isEmpty {
                if !cursorBarVisible { toggleCursorBar() }
            } else {
                selectNextCandidate()
            }
            return
        }
        if definition.action == "space", value == "__cursor_repeat__" {
            if dictionaryMode == .edit { return }
            textDocumentProxy.adjustTextPosition(byCharacterOffset: -1)
            refreshCursorBar()
            return
        }
        if definition.action == "space", value.hasPrefix("__cursor_drag__:") {
            if dictionaryMode == .edit { return }
            let delta = Int(value.dropFirst("__cursor_drag__:".count)) ?? 0
            textDocumentProxy.adjustTextPosition(byCharacterOffset: delta)
            refreshCursorBar()
            return
        }
        guard let action = definition.action else {
            input(value)
            return
        }
        switch action {
        case "delete":
            if value == "×" { smartDeleteDefault() }
            else if value == "__delete_repeat__" { delete() }
            else if value.hasPrefix("__delete_drag__:") {
                let count = min(100, max(0, Int(value.dropFirst("__delete_drag__:".count)) ?? 0))
                for _ in 0 ..< count { delete() }
            }
            else { quickDelete() }
        case "space":
            switch value {
            case "←": textDocumentProxy.adjustTextPosition(byCharacterOffset: -1); refreshCursorBar()
            case "貼付":
                if boolSetting("enable_paste_button_on_flick_cursorbar_key", fallback: false) {
                    if hasFullAccess, let text = UIPasteboard.general.string { directCommit(text) }
                }
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
        case "upperLowerEnglish": pressAa()
        case "nextKeyboard": advanceToNextInputMode()
        default: break
        }
    }

    private func transformLastCharacter() {
        if let last = composing.last {
            let character = String(last)
            let value: String
            if mode == "english", character.range(of: #"^[A-Za-z]$"#, options: .regularExpression) != nil {
                value = character == character.uppercased() ? character.lowercased() : character.uppercased()
            } else {
                value = kanaCharacterForms[character] ?? character
            }
            composing.removeLast()
            composing += value
            updateComposition()
        } else if let last = textDocumentProxy.documentContextBeforeInput?.last {
            let character = String(last)
            let value: String
            if mode == "english", character.range(of: #"^[A-Za-z]$"#, options: .regularExpression) != nil {
                value = character == character.uppercased() ? character.lowercased() : character.uppercased()
            } else {
                guard let transformed = kanaCharacterForms[character] else { return }
                value = transformed
            }
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(value)
        }
    }

    private func dispatch(
        _ action: [String: Any]?,
        allowQuickWordDelete: Bool = false
    ) {
        guard let action else { return }
        let type = action["type"] as? String ?? "input"
        let value = action["value"] as? String ?? ""
        if dictionaryMode == .edit && ![
            "input", "directInput", "direct_input", "delete", "enter", "space",
            "switchLayout", "paste", "__paste", "smart_delete_default", "smartDeleteDefault",
            "smart_delete", "toggle_caps_lock_state", "toggleCapsLock", "dismiss", "dismiss_keyboard"
        ].contains(type) { return }
        switch type {
        case "input":
            if let text = action["text"] as? String { custardInput(text) } else { customInput(value) }
        case "directInput": directCommit(value, normalizePunctuation: false)
        case "direct_input": directCommit(action["text"] as? String ?? "", normalizePunctuation: false)
        case "delete":
            if dictionaryMode != .edit, deleteSelectedText() { return }
            let count = (action["count"] as? NSNumber)?.intValue ?? Int(value) ?? 1
            let boundedCount = min(100, max(-100, count))
            if allowQuickWordDelete, boundedCount == 1 {
                quickDelete()
            } else if boundedCount > 0 {
                for _ in 0 ..< boundedCount { delete() }
            } else if boundedCount < 0 {
                for _ in 0 ..< -boundedCount { deleteForward() }
            }
        case "enter": enter()
        case "space": spaceWithoutConversion()
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

    private func dispatch(
        _ actions: [[String: Any]],
        allowQuickWordDelete: Bool = false
    ) {
        var index = 0
        while index < actions.count {
            if index + 1 < actions.count,
               positiveBackwardDelete(actions[index]),
               isBackwardSmartDelete(actions[index + 1]) {
                if dictionaryMode == .edit { deleteDictionaryText() }
                else {
                    dispatchCombinedBackwardSmartDelete(
                        deleteAction: actions[index],
                        smartDeleteAction: actions[index + 1]
                    )
                }
                index += 2
            } else {
                dispatch(
                    actions[index],
                    allowQuickWordDelete: allowQuickWordDelete
                )
                index += 1
            }
        }
    }

    private func positiveBackwardDelete(_ action: [String: Any]) -> Bool {
        guard action["type"] as? String == "delete" else { return false }
        let count = (action["count"] as? NSNumber)?.intValue
            ?? Int(action["value"] as? String ?? "")
            ?? 1
        return count > 0
    }

    private func isBackwardSmartDelete(_ action: [String: Any]) -> Bool {
        switch action["type"] as? String {
        case "smart_delete_default", "smartDeleteDefault": return true
        case "smart_delete": return action["direction"] as? String == "backward"
        default: return false
        }
    }

    private func backwardWordDeleteCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        var contentEnd = text.endIndex
        while contentEnd > text.startIndex {
            let previous = text.index(before: contentEnd)
            guard text[previous].isWhitespace else { break }
            contentEnd = previous
        }
        if contentEnd == text.startIndex { return text.count }

        var lastWord: Range<String.Index>?
        text.enumerateSubstrings(
            in: text.startIndex ..< contentEnd,
            options: [.byWords, .substringNotRequired]
        ) { _, range, _, _ in
            lastWord = range
        }
        if let lastWord {
            let start = lastWord.upperBound == contentEnd
                ? refinedJapaneseWordStart(
                    in: text,
                    start: lastWord.lowerBound,
                    end: lastWord.upperBound
                )
                : lastWord.upperBound
            return text.distance(from: start, to: text.endIndex)
        }

        let previous = text.index(before: contentEnd)
        return text.distance(from: previous, to: text.endIndex)
    }

    private enum JapaneseCharacterClass {
        case hiragana, katakana, han, latin, digit, other
    }

    private static let japaneseParticles = [
        "から", "まで", "より", "ので", "のに", "では", "には", "とは", "って",
        "を", "が", "は", "も", "の", "に", "へ", "で", "と", "や",
    ]

    private static let japaneseAuxiliaries = [
        "ませんでした", "ましょう", "ました", "ません", "ます",
        "でした", "でしょう", "です", "だった", "だろう", "ない", "たい",
    ]

    private static let indivisibleKanaWords: Set<String> = [
        "こんにちは", "こんばんは", "ありがとう", "おはよう",
    ]

    /// Refines one platform word without ever extending its deletion range.
    private func refinedJapaneseWordStart(
        in text: String,
        start: String.Index,
        end: String.Index
    ) -> String.Index {
        guard start < end else { return start }
        let finalClass = japaneseCharacterClass(text[text.index(before: end)])
        var runStart = end
        var cursor = end
        while cursor > start {
            let previous = text.index(before: cursor)
            guard japaneseCharacterClass(text[previous]) == finalClass else { break }
            runStart = previous
            cursor = previous
        }
        return refineKanaGrammarBoundary(in: text, start: runStart, end: end)
    }

    private func refineKanaGrammarBoundary(
        in text: String,
        start: String.Index,
        end: String.Index
    ) -> String.Index {
        guard start < end else { return start }
        let segment = String(text[start ..< end])
        guard !Self.indivisibleKanaWords.contains(segment), Self.systemDictionary[segment] == nil,
              segment.allSatisfy({ japaneseCharacterClass($0) == .hiragana }) else {
            return start
        }

        if let suffix = Self.japaneseAuxiliaries.first(where: {
            segment.count > $0.count && segment.hasSuffix($0)
        }) {
            return text.index(end, offsetBy: -suffix.count)
        }
        // In an all-kana run, は/の/に may be part of the word itself.
        // を is a safer boundary without a morphological tokenizer.
        if segment.count > 1, segment.hasSuffix("を") {
            return text.index(before: end)
        }
        if let marker = text.range(of: "を", options: .backwards, range: start ..< end),
           text.distance(from: start, to: marker.lowerBound) >= 2,
           text.distance(from: marker.upperBound, to: end) >= 2 {
            return marker.upperBound
        }
        for particle in Self.japaneseParticles where segment.count > particle.count && segment.hasSuffix(particle) {
            if Self.systemDictionary[String(segment.dropLast(particle.count))] != nil {
                return text.index(end, offsetBy: -particle.count)
            }
        }
        for particle in Self.japaneseParticles {
            guard let range = text.range(of: particle, options: .backwards, range: start ..< end) else { continue }
            let prefix = String(text[start ..< range.lowerBound])
            let suffix = String(text[range.upperBound ..< end])
            if prefix.count >= 2, suffix.count >= 2,
               Self.systemDictionary[prefix] != nil, Self.systemDictionary[suffix] != nil {
                return range.upperBound
            }
        }
        return start
    }

    private func japaneseCharacterClass(_ character: Character) -> JapaneseCharacterClass {
        guard let value = character.unicodeScalars.first?.value else { return .other }
        switch value {
        case 0x3040 ... 0x309F: return .hiragana
        case 0x30A0 ... 0x30FF, 0xFF66 ... 0xFF9D: return .katakana
        case 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF, 0xF900 ... 0xFAFF: return .han
        case 0x30 ... 0x39: return .digit
        case 0x41 ... 0x5A, 0x61 ... 0x7A: return .latin
        default: return .other
        }
    }

    private func dispatchCombinedBackwardSmartDelete(
        deleteAction _: [String: Any],
        smartDeleteAction _: [String: Any]
    ) {
        // Ogura-style layouts express one word deletion as `delete` followed
        // by backward smart-delete. Resolve the pair atomically before the
        // leading delete can consume a one-character Japanese word.
        smartDeleteDefault()
    }

    private func activeCustard() -> [String: Any]? {
        guard let id = activeCustomTab else { return nil }
        return (state["custards"] as? [[String: Any]])?.first { $0["identifier"] as? String == id }
    }

    private func customTabDefinition(_ id: String) -> [String: Any]? {
        (state["customTabs"] as? [[String: Any]])?.first {
            ($0["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == id
        }
    }

    private func customLayoutProfile(_ id: String) -> (language: String, inputStyle: String)? {
        if let tab = customTabDefinition(id) {
            return (
                tab["language"] as? String ?? "ja_JP",
                tab["inputStyle"] as? String ?? "direct"
            )
        }
        if let custard = (state["custards"] as? [[String: Any]])?.first(where: {
            $0["identifier"] as? String == id
        }) {
            return (
                custard["language"] as? String ?? "undefined",
                custard["input_style"] as? String ?? "direct"
            )
        }
        return nil
    }

    private func activateCustomLayout(_ id: String) {
        activeCustomTab = id
        guard let profile = customLayoutProfile(id) else { return }
        switch profile.language {
        case "en_US":
            mode = "english"
            layout = "qwerty"
        case "ja_JP":
            mode = "japanese"
            layout = profile.inputStyle == "roman2kana" ? "qwerty" : "flick"
        default:
            break
        }
    }

    private func switchToCustomLayout(_ rawID: String) {
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let profile = customLayoutProfile(id) else { return }
        // Custard Shift/Caps Lock can be separate tabs, with an input action
        // followed by move_tab to return. Neither move should accept the word.
        if mode != "english" || profile.language != "en_US" { commitComposition() }
        activateCustomLayout(id)
        renderCandidates()
        renderKeyboard()
    }

    private var shouldUppercaseEnglishLabels: Bool {
        mode == "english" && (shift || capsLock || textDocumentProxy.autocapitalizationType == .allCharacters)
    }

    private func customInput(_ value: String) {
        guard !value.isEmpty else { return }
        guard let id = activeCustomTab, let tab = customTabDefinition(id) else {
            input(value)
            return
        }
        let language = tab["language"] as? String ?? "ja_JP"
        let inputStyle = tab["inputStyle"] as? String ?? "direct"
        switch language {
        case "en_US":
            mode = "english"
            layout = "qwerty"
            inputEnglishText(value)
        case "ja_JP":
            mode = "japanese"
            layout = inputStyle == "roman2kana" ? "qwerty" : "flick"
            input(value)
        default:
            directCommit(value)
        }
    }

    private func makeCustardInputRollback(
        startActions: [[String: Any]],
        repeatActions: [[String: Any]]
    ) -> (() -> Void)? {
        guard activeCustard()?["language"] as? String == "ja_JP" else { return nil }
        let actions = startActions + repeatActions
        guard !actions.isEmpty, actions.allSatisfy({ action in
            guard (action["type"] as? String ?? "input") == "input",
                  let text = action["text"] as? String,
                  !text.isEmpty else { return false }
            return !text.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
        }) else { return nil }

        let savedComposing = composing
        let savedRawRoman = rawRoman
        let savedMode = mode
        let savedLayout = layout
        return { [weak self] in
            guard let self else { return }
            self.composing = savedComposing
            self.rawRoman = savedRawRoman
            self.mode = savedMode
            self.layout = savedLayout
            if savedComposing.isEmpty, savedRawRoman.isEmpty {
                self.replaceDisplayed(with: "", commit: true)
                self.candidates = []
                self.renderCandidates()
            } else {
                self.updateComposition()
            }
        }
    }

    private func custardInput(_ value: String) {
        guard !value.isEmpty else { return }
        if value.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains) {
            directCommit(value)
            return
        }
        let custard = activeCustard()
        let language = custard?["language"] as? String ?? "undefined"
        let inputStyle = custard?["input_style"] as? String ?? "direct"
        if language == "en_US" {
            mode = "english"
            inputEnglishText(value)
            return
        }
        guard language == "ja_JP" else {
            directCommit(value)
            return
        }
        if closingDelimiter(for: value) != nil {
            mode = "japanese"
            directCommit(value)
            return
        }
        // Direct-style Japanese Custards use ASCII as literal text rather than
        // kana-kanji input. Commit it immediately so template/snippet keys never
        // enter live conversion or become full-width candidates.
        if inputStyle == "direct", value.unicodeScalars.allSatisfy({ $0.value <= 0x7F }) {
            directCommit(value, normalizePunctuation: false)
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
              let replacement = kanaCharacterForms[String(last)] else { return }
        textDocumentProxy.deleteBackward()
        textDocumentProxy.insertText(replacement)
    }

    private func replaceLastCharacters(_ table: [String: String]?) {
        guard let table else { return }
        let source = composing.isEmpty ? (textDocumentProxy.documentContextBeforeInput ?? "") : composing
        let removedCount: Int
        let replacement: String
        if let match = table.keys.filter(source.hasSuffix).max(by: { $0.count < $1.count }),
           let exactReplacement = table[match] {
            removedCount = match.count
            replacement = exactReplacement
        } else if let fallback = characterFormFallback(for: source, table: table) {
            removedCount = fallback.removedCount
            replacement = fallback.replacement
        } else {
            return
        }
        if composing.isEmpty {
            for _ in 0 ..< removedCount { textDocumentProxy.deleteBackward() }
            textDocumentProxy.insertText(replacement)
        } else {
            composing.removeLast(removedCount)
            composing += replacement
            updateComposition()
        }
    }

    private func characterFormFallback(
        for source: String,
        table: [String: String]
    ) -> (removedCount: Int, replacement: String)? {
        let formEntries = table.compactMap { entrySource, entryReplacement -> (String, String, String)? in
            guard entrySource.count == 2, entryReplacement.count == 1,
                  let character = entrySource.first,
                  let marker = entrySource.last,
                  sharesKanaCharacterFormCycle(String(character), entryReplacement) else { return nil }
            return (String(character), String(marker), entryReplacement)
        }
        for marker in Set(formEntries.map { $0.1 }) {
            guard source.hasSuffix(marker) else { continue }
            let sourceWithoutMarker = source.dropLast()
            guard let lastCharacter = sourceWithoutMarker.last else { continue }
            let last = String(lastCharacter)
            guard formEntries.contains(where: {
                $0.1 == marker && ($0.0 == last || $0.2 == last)
            }), let replacement = kanaCharacterForms[last] else { continue }
            return (removedCount: 2, replacement: replacement)
        }
        return nil
    }

    private func sharesKanaCharacterFormCycle(_ first: String, _ second: String) -> Bool {
        var visited = Set<String>()
        var current = first
        while visited.insert(current).inserted {
            guard let next = kanaCharacterForms[current] else { return false }
            if next == second { return true }
            current = next
        }
        return false
    }

    private func actionTargets(_ action: [String: Any]) -> [String] {
        action["targets"] as? [String] ?? Self.defaultScanTargets
    }

    private func smartDeleteDefault() {
        if dictionaryMode == .edit { deleteDictionaryText(); return }
        if deleteSelectedText() { return }
        if !composing.isEmpty || !rawRoman.isEmpty {
            let count = backwardWordDeleteCount(in: composing)
            let remaining = String(composing.dropLast(min(count, composing.count)))
            if !rawRoman.isEmpty {
                guard let remainingRaw = rawRomanPrefix(forComposition: remaining) else {
                    replaceDisplayed(with: "", commit: true)
                    resetComposition()
                    renderCandidates()
                    return
                }
                rawRoman = remainingRaw
            }
            composing = remaining
            if composing.isEmpty {
                replaceDisplayed(with: "", commit: true)
                resetComposition()
                renderCandidates()
            } else {
                updateComposition()
            }
            return
        }
        let text = textDocumentProxy.documentContextBeforeInput ?? ""
        let count = backwardWordDeleteCount(in: text)
        for _ in 0 ..< count { textDocumentProxy.deleteBackward() }
        refreshCursorBar()
    }

    private func rawRomanPrefix(forComposition expected: String) -> String? {
        var end = rawRoman.endIndex
        while true {
            let prefix = String(rawRoman[..<end])
            if romanToHiragana(prefix) == expected { return prefix }
            if end == rawRoman.startIndex { return nil }
            end = rawRoman.index(before: end)
        }
    }

    private func smartDelete(_ action: [String: Any]) {
        if dictionaryMode == .edit { deleteDictionaryText(); return }
        if deleteSelectedText() { return }
        let backward = action["direction"] as? String == "backward"
        if backward {
            // Custard smart-delete is the layout-level word-delete gesture.
            // Share the same linguistic boundary detector as double delete.
            smartDeleteDefault()
            return
        }
        let targets = actionTargets(action)
        if !composing.isEmpty || !rawRoman.isEmpty {
            // The local composition cursor is at its trailing edge, so a
            // forward smart-delete has nothing to remove until it is committed.
            return
        }
        let text = textDocumentProxy.documentContextAfterInput ?? ""
        let distances = targets.compactMap { target -> Int? in
            guard let range = text.range(of: target) else { return nil }
            return text.distance(from: text.startIndex, to: range.lowerBound)
        }
        let distance = distances.min() ?? text.count
        let count = distance == 0 && !text.isEmpty ? 1 : distance
        textDocumentProxy.adjustTextPosition(byCharacterOffset: count)
        for _ in 0 ..< count { textDocumentProxy.deleteBackward() }
        refreshCursorBar()
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
        selectedCandidateText = candidates[index.clamped(to: 0 ... candidates.count - 1)]
        replaceDisplayed(with: selectedCandidateText!, commit: false)
        renderCandidates(showTabs: false)
    }

    private func completeCharacterForm(_ forms: [String]?) {
        guard !composing.isEmpty else { return }
        let caseConverted: String?
        switch forms?.first {
        case "uppercase": caseConverted = composing.uppercased()
        case "lowercase": caseConverted = composing.lowercased()
        default: caseConverted = nil
        }
        if let caseConverted {
            // Custom English layouts can keep the Japanese mode identifier.
            // Leave the replacement active so later input continues the word.
            composing = caseConverted
            rawRoman = ""
            updateComposition()
            return
        }
        let converted: String
        switch forms?.first {
        case "hiragana": converted = katakanaToHiragana(composing)
        case "katakana": converted = hiraganaToKatakana(composing)
        case "halfwidth_katakana": converted = hiraganaToKatakana(composing).applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? composing
        default: converted = composing
        }
        replaceDisplayed(with: converted, commit: true)
        resetComposition()
        renderCandidates()
    }

    private func moveTab(_ action: [String: Any]) {
        if action["tab_type"] as? String == "custom" {
            switchToCustomLayout(action["identifier"] as? String ?? "")
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
        if self.mode != "english" || mode != "english" { commitComposition() }
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
        candidatePredictionReadings = [:]
        unknownPredictionTexts = []
        guard !composing.isEmpty else { return [] }
        if mode == "english" { return buildEnglishCandidates(composing) }
        let reading = katakanaToHiragana(composing)
        let activeConversionEntries = conversionDictionaryEntries.filter { entry in
            let ruby = katakanaToHiragana(entry.ruby)
            return !ruby.isEmpty && (reading.contains(ruby) || ruby.hasPrefix(reading))
        }
        var result: [String] = []
        var exactUserTexts: [String] = []
        let allLearned = learnedCandidateEntries(learningScores(), english: false)
        let learned = allLearned
            .filter { $0.reading.hasPrefix(reading) }
            .sorted { $0.score > $1.score }
        let learnedPrefixes = learned.filter { $0.reading != reading }
        var prefixPredictions = learnedPrefixes.map(\.text)
        var registeredPrefixPredictions: [(text: String, ruby: String, importance: Int)] = []
        var predictionReadings: [String: String] = [:]
        for entry in learnedPrefixes {
            if predictionReadings[entry.text] == nil { predictionReadings[entry.text] = entry.reading }
        }
        if let dictionary = state["userDictionary"] as? [[String: Any]] {
            let ranked = dictionary.sorted {
                let left = $0["importance"] as? Int ?? 3
                let right = $1["importance"] as? Int ?? 3
                let leftRuby = $0["ruby"] as? String ?? ""
                let rightRuby = $1["ruby"] as? String ?? ""
                let leftRemaining = max(0, katakanaToHiragana(leftRuby).count - reading.count)
                let rightRemaining = max(0, katakanaToHiragana(rightRuby).count - reading.count)
                let leftScore = min(5, max(1, left)) * 20 - min(1000, leftRemaining) * 4
                let rightScore = min(5, max(1, right)) * 20 - min(1000, rightRemaining) * 4
                if leftScore != rightScore { return leftScore > rightScore }
                if leftRuby.count != rightRuby.count { return leftRuby.count < rightRuby.count }
                return leftRuby < rightRuby
            }
            for entry in ranked {
                guard let rawRuby = entry["ruby"] as? String else { continue }
                let ruby = katakanaToHiragana(rawRuby)
                guard ruby.hasPrefix(reading) else { continue }
                let value: String?
                if entry["isTemplateMode"] as? Bool == true {
                    value = renderTemplate(entry["formatLiteral"] as? String ?? "")
                } else {
                    value = entry["word"] as? String
                }
                guard let value, !value.isEmpty else { continue }
                if ruby == reading {
                    result.append(value)
                    exactUserTexts.append(value)
                } else {
                    prefixPredictions.append(value)
                    registeredPrefixPredictions.append((
                        text: value,
                        ruby: ruby,
                        importance: entry["importance"] as? Int ?? 3
                    ))
                    if predictionReadings[value] == nil { predictionReadings[value] = ruby }
                }
            }
        }
        let sharedPrefixEntries = activeConversionEntries.filter {
            let ruby = katakanaToHiragana($0.ruby)
            return ruby.count > reading.count && ruby.hasPrefix(reading) && !$0.word.isEmpty
        }.sorted {
            let left = katakanaToHiragana($0.ruby)
            let right = katakanaToHiragana($1.ruby)
            if left.count != right.count { return left.count < right.count }
            return $0.wordWeight > $1.wordWeight
        }
        for entry in sharedPrefixEntries.prefix(32) {
            let ruby = katakanaToHiragana(entry.ruby)
            guard ruby.count > reading.count, ruby.hasPrefix(reading), !entry.word.isEmpty else { continue }
            let weightImportance = (entry.wordWeight + 9) / 2 + 3
            let importance = weightImportance.isFinite
                ? Int(min(5, max(1, weightImportance))) : 3
            registeredPrefixPredictions.append((
                text: entry.word,
                ruby: ruby,
                importance: importance
            ))
            prefixPredictions.append(entry.word)
            if predictionReadings[entry.word] == nil { predictionReadings[entry.word] = ruby }
        }
        let zenzai = zenzaiConfiguration()
        let blockedEmoji = blockedAdditionalEmoji()
        let engineCandidates = (conversionEngine?.candidates(
            reading: composing,
            rawRoman: layout == "qwerty" ? rawRoman : nil,
            leftContext: textDocumentProxy.documentContextBeforeInput,
            rightContext: textDocumentProxy.documentContextAfterInput,
            modelURL: zenzai?.url,
            inferenceLimit: zenzai?.inferenceLimit ?? 1,
            learningMode: intSetting("memory_learining_styple_setting", fallback: 0),
            automaticCompletionStrength: boolSetting("live_conversion", fallback: true)
                ? intSetting("automatic_completion_strength", fallback: 1) : 0,
            englishCandidateInRoman2KanaInput: boolSetting("roman_english_candidate", fallback: true),
            typographyCandidate: boolSetting("typography_roman_candidate", fallback: true),
            fullWidthRomanCandidate: boolSetting("full_roman_candidate", fallback: true),
            halfWidthKanaCandidate: boolSetting("half_kana_candidate", fallback: true),
            unicodeCandidate: boolSetting("unicode_candidate", fallback: true),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.1.0"
        ) ?? []).filter { !blockedEmoji.contains(Self.normalizedEmoji($0)) || exactUserTexts.contains($0) }
        let enginePredictionTexts = conversionEngine?.predictionTexts ?? []
        result.append(contentsOf: engineCandidates.filter { !enginePredictionTexts.contains($0) })
        let registeredCombinationEntries = activeConversionEntries.map {
            (ruby: $0.ruby, word: $0.word, importance: 3)
        }
        let registeredCombinations = dictionaryCombinations(
            reading, entries: registeredCombinationEntries, limit: 32
        )
        let combinedTexts = Array(registeredCombinations.prefix(8))
        let learnedCombinationEntries = allLearned.filter { reading.contains($0.reading) }
            .map { (ruby: $0.reading, word: $0.text, importance: min(5, 3 + $0.score / 16)) }
        let allCombinationEntries = registeredCombinationEntries + learnedCombinationEntries
        let activeCombinationEntries = allCombinationEntries.filter {
            !$0.ruby.isEmpty && !$0.word.isEmpty &&
                reading.contains(katakanaToHiragana($0.ruby))
        }
        let exactRegisteredTexts = Set(exactUserTexts + allLearned.filter {
            $0.reading == reading
        }.map(\.text))
        let trustedCompleteTexts: Set<String> = hasLongOrdinaryGapBetweenRegisteredWords(
            reading, entries: activeCombinationEntries
        ) ? Set(conversionEngine?.baselineTexts ?? []) : []
        let hasExactPair = activeCombinationEntries.count >= 2 && !dictionaryCombinations(
            reading, entries: activeCombinationEntries, limit: 1, minimumRegisteredWords: 2
        ).isEmpty
        let blockedCombinedValues: [String] = hasExactPair ? [] :
            Array(Set(activeCombinationEntries.map(\.word)))
        let incompleteCombinationTexts: Set<String> = activeCombinationEntries.count < 2 ? [] :
            Set(dictionaryCombinations(
                reading, entries: activeCombinationEntries, limit: 128,
                requireBoundaryMatches: false, minimumRegisteredWords: 2
            )).subtracting(dictionaryCombinations(
                reading, entries: activeCombinationEntries, limit: 128,
                minimumRegisteredWords: 2
            )).subtracting(exactRegisteredTexts)
        let normalizedIncompleteCombinationTexts = Set(
            incompleteCombinationTexts.map(katakanaToHiragana)
        )
        let registeredTexts = Set(registeredCombinations)
        var learnedCombinationTexts = dictionaryCombinations(
            reading, entries: learnedCombinationEntries
        )
        learnedCombinationTexts.append(contentsOf: dictionaryCombinations(
            reading, entries: registeredCombinationEntries + learnedCombinationEntries, limit: 32
        ).filter { !registeredTexts.contains($0) })
        var seenLearnedCombination = Set<String>()
        learnedCombinationTexts = Array(learnedCombinationTexts.filter {
            seenLearnedCombination.insert($0).inserted
        }.prefix(8))
        result.append(contentsOf: combinedTexts)
        result.append(contentsOf: learnedCombinationTexts)
        prefixPredictions.append(contentsOf: engineCandidates.filter { enginePredictionTexts.contains($0) })
        if boolSetting("use_OS_user_dict", fallback: true) {
            for ruby in osLexicon.keys.sorted(by: {
                $0.count == $1.count ? $0 < $1 : $0.count < $1.count
            }) {
                let normalized = katakanaToHiragana(ruby)
                if normalized == reading {
                    result.append(contentsOf: osLexicon[ruby] ?? [])
                } else if normalized.hasPrefix(reading) {
                    for value in osLexicon[ruby] ?? [] {
                        prefixPredictions.append(value)
                        if predictionReadings[value] == nil { predictionReadings[value] = normalized }
                    }
                }
            }
        }
        result.append(contentsOf: Self.systemDictionary[reading] ?? [])
        for ruby in Self.systemDictionary.keys.sorted(by: {
            $0.count == $1.count ? $0 < $1 : $0.count < $1.count
        }) where ruby.count > reading.count && ruby.hasPrefix(reading) {
            for value in Self.systemDictionary[ruby] ?? [] {
                prefixPredictions.append(value)
                if predictionReadings[value] == nil { predictionReadings[value] = ruby }
            }
        }
        // The model may return the same text as a registered or learned
        // completion. Keep its longer reading when ranking live candidates.
        let knownPrefixTexts = Set(registeredPrefixPredictions.map(\.text) + learnedPrefixes.map(\.text))
            .subtracting(exactUserTexts)
        // A local completion must not become a live conversion while its
        // reading is unfinished.
        var completeTexts = Set<String>()
        result = result.filter { !$0.isEmpty && completeTexts.insert($0).inserted }
        completeTexts.subtract(knownPrefixTexts)
        if result.isEmpty {
            result = [reading, hiraganaToKatakana(reading)]
            completeTexts = Set(result)
        }
        var predictionTexts = completeTexts
        let predictions = prefixPredictions.filter {
            !$0.isEmpty && predictionTexts.insert($0).inserted
        }.prefix(32)
        result.insert(contentsOf: predictions, at: min(3, result.count))
        result.append(composing)
        let katakana = hiraganaToKatakana(composing)
        if katakana != composing { result.append(katakana) }
        if boolSetting("emoji_dictionary_enabled", fallback: true) {
            result.append(contentsOf: (Self.emojiDictionary[composing] ?? []).filter {
                !blockedEmoji.contains(Self.normalizedEmoji($0))
            })
        }
        if boolSetting("kaomoji_dictionary_enabled", fallback: false) {
            result.append(contentsOf: Self.kaomojiDictionary[composing] ?? [])
        }
        if layout == "qwerty", boolSetting("roman_english_candidate", fallback: true), !rawRoman.isEmpty {
            result.append(rawRoman)
        }
        let exactLearning = learned.filter { $0.reading == reading }
        let exactTexts = completeTexts.union(exactLearning.map(\.text))
            .union(learnedCombinationTexts)
        candidatePredictionReadings = predictionReadings.filter { !exactTexts.contains($0.key) }
        unknownPredictionTexts = enginePredictionTexts.subtracting(exactTexts)
            .subtracting(Set(candidatePredictionReadings.keys))
        let hiragana = katakanaToHiragana(composing)
        let fullKatakana = hiraganaToKatakana(hiragana)
        let predictedTexts = Set(candidatePredictionReadings.keys).union(unknownPredictionTexts)
        let partialTexts = Set(activeConversionEntries.compactMap { entry -> String? in
            let ruby = katakanaToHiragana(entry.ruby)
            guard !ruby.isEmpty, reading.count > ruby.count, reading.hasPrefix(ruby) else { return nil }
            return entry.word + String(reading.dropFirst(ruby.count))
        })
        // The official converter already scores registered words, grammar and
        // learned paths in its lattice. Preserve its result order here.
        let officialComplete = engineCandidates.filter {
            !predictedTexts.contains($0) && !knownPrefixTexts.contains($0)
                && !partialTexts.contains($0)
        }
        let localComplete = result.filter {
            !predictedTexts.contains($0) && !knownPrefixTexts.contains($0)
                && !partialTexts.contains($0)
        }
        let prefixCandidates = registeredPrefixPredictions.map(\.text)
            + learnedPrefixes.map(\.text) + prefixPredictions
            + result.filter { partialTexts.contains($0) }
        var seen = Set<String>()
        let ordered = (officialComplete + exactUserTexts + exactLearning.map(\.text)
            + combinedTexts + learnedCombinationTexts + localComplete
            + prefixCandidates + [hiragana, fullKatakana, composing, rawRoman]).filter { candidate in
            guard !candidate.isEmpty else { return false }
            if !exactRegisteredTexts.contains(candidate) {
                if normalizedIncompleteCombinationTexts.contains(katakanaToHiragana(candidate)) {
                    return false
                }
                if !trustedCompleteTexts.contains(candidate) &&
                    blockedCombinedValues.filter({ candidate.contains($0) }).count >= 2 {
                    return false
                }
            }
            return seen.insert(candidate).inserted
        }
        let hasStrongLearning = exactLearning.contains { $0.score >= 4 }
        let hasExactRegistration = !exactUserTexts.isEmpty || hasStrongLearning ||
            activeConversionEntries.contains { katakanaToHiragana($0.ruby) == reading }
        let baselineLeadingTexts = conversionEngine.map {
            Array($0.baselineTexts.prefix(2))
        } ?? []
        let literalReadingFirst = baselineLeadingTexts.first == hiragana ||
            (reading.count <= 2 && baselineLeadingTexts.first == fullKatakana &&
             baselineLeadingTexts.contains(hiragana))
        if !hasExactRegistration, literalReadingFirst, ordered.contains(hiragana) {
            return [hiragana] + ordered.filter { $0 != hiragana }
        }
        if !hasExactRegistration, reading == "ないか", ordered.contains("無いか") {
            return ["無いか"] + ordered.filter { $0 != "無いか" }
        }
        if !hasExactRegistration, let first = ordered.first,
           (first.unicodeScalars.contains(where: { $0.value >= 65 && $0.value <= 90 }) ||
            (first.unicodeScalars.contains(where: { $0.value >= 0x3041 && $0.value <= 0x3096 }) &&
             first.unicodeScalars.contains(where: { $0.value >= 0x30A1 && $0.value <= 0x30F6 }))),
           officialComplete.contains(fullKatakana) {
            return [fullKatakana] + ordered.filter { $0 != fullKatakana }
        }
        return ordered
    }

    private func blockedAdditionalEmoji() -> Set<String> {
        var blocked = Set<String>()
        if boolSetting("hide_cockroach_emoji", fallback: false) { blocked.insert("🪳") }
        if boolSetting("hide_mosquito_emoji", fallback: false) { blocked.insert("🦟") }
        if boolSetting("hide_spider_emoji", fallback: false) { blocked.formUnion(["🕸", "🕷"]) }
        if boolSetting("hide_worm_emoji", fallback: false) { blocked.insert("🪱") }
        return blocked
    }

    private static func normalizedEmoji(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{FE0F}", with: "")
            .replacingOccurrences(of: "\u{FE0E}", with: "")
    }

    private static let combinationConnectors = [
        "は", "が", "を", "に", "へ", "で", "と", "も", "の", "や", "か", "ね", "よ",
        "から", "まで", "より", "だけ", "など", "しか", "こそ", "でも",
        "です", "でした", "だ", "だった", "ます", "ました"
    ].map { Array($0) }
    private func isCombinationConnector(_ value: String) -> Bool {
        if value.isEmpty { return true }
        let characters = Array(value)
        var reachable = Array(repeating: false, count: characters.count + 1)
        reachable[0] = true
        for index in characters.indices where reachable[index] {
            for connector in Self.combinationConnectors where index + connector.count <= characters.count {
                if characters[index..<(index + connector.count)].elementsEqual(connector) {
                    reachable[index + connector.count] = true
                }
            }
        }
        return reachable[characters.count]
    }

    private func hasLongOrdinaryGapBetweenRegisteredWords(
        _ reading: String, entries: [(ruby: String, word: String, importance: Int)]
    ) -> Bool {
        let characters = Array(reading)
        var spans: [(start: Int, end: Int)] = []
        for entry in entries where !entry.word.isEmpty {
            let ruby = Array(katakanaToHiragana(entry.ruby))
            guard !ruby.isEmpty, ruby.count <= characters.count else { continue }
            for start in 0...(characters.count - ruby.count) where
                characters[start..<(start + ruby.count)].elementsEqual(ruby) {
                spans.append((start, start + ruby.count))
            }
        }
        for first in spans {
            for second in spans where second.start >= first.end {
                let gaps = [
                    String(characters[0..<first.start]),
                    String(characters[first.end..<second.start]),
                    String(characters[second.end..<characters.count])
                ]
                if gaps.allSatisfy({ isCombinationConnector($0) || $0.count >= 3 }) &&
                    gaps.contains(where: { $0.count >= 3 && !isCombinationConnector($0) }) {
                    return true
                }
            }
        }
        return false
    }

    private func dictionaryCombinations(
        _ reading: String, entries: [(ruby: String, word: String, importance: Int)],
        limit: Int = 8, requireBoundaryMatches: Bool = true,
        minimumRegisteredWords: Int = 1
    ) -> [String] {
        struct Match {
            let end: Int
            let value: String
            let score: Int
            let registered: Bool
        }
        struct Path {
            let text: String
            let score: Int
            let words: Int
            let registeredWords: Int
            let startsWithWord: Bool
            let pendingKana: String
            let validConnectors: Bool
        }
        let characters = Array(reading)
        if characters.count < 2 || entries.isEmpty { return [] }
        var matches = Array(repeating: [Match](), count: characters.count)
        var hasRegisteredMatch = false
        func add(_ rawRuby: String, _ value: String, _ importance: Int, _ registered: Bool) {
            let normalized = katakanaToHiragana(rawRuby)
            guard reading.contains(normalized) else { return }
            let ruby = Array(normalized)
            guard !ruby.isEmpty, !value.isEmpty, ruby.count <= characters.count else { return }
            for start in 0...(characters.count - ruby.count) {
                guard characters[start..<(start + ruby.count)].elementsEqual(ruby) else { continue }
                matches[start].append(Match(
                    end: start + ruby.count,
                    value: value,
                    score: (registered ? ruby.count * 18 - 28 : ruby.count * 15 - 30)
                        + min(5, max(1, importance)) * 4,
                    registered: registered
                ))
                if registered { hasRegisteredMatch = true }
            }
        }
        for entry in entries {
            add(entry.ruby, entry.word, entry.importance, true)
        }
        if !hasRegisteredMatch { return [] }
        for (ruby, values) in Self.systemDictionary {
            for value in values.prefix(2) { add(ruby, value, 3, false) }
        }

        var beams = Array(repeating: [Path](), count: characters.count + 1)
        beams[0].append(Path(text: "", score: 0, words: 0, registeredWords: 0,
                             startsWithWord: false, pendingKana: "", validConnectors: true))
        func push(_ end: Int, _ path: Path) {
            beams[end].append(path)
            if beams[end].count > 48 {
                beams[end].sort { $0.score > $1.score }
                let count = beams[end].count
                beams[end].removeSubrange(16..<count)
            }
        }
        for index in characters.indices {
            let current = beams[index].sorted { $0.score > $1.score }.prefix(16)
            for path in current {
                push(index + 1, Path(
                    text: path.text + String(characters[index]),
                    score: path.score - 3,
                    words: path.words,
                    registeredWords: path.registeredWords,
                    startsWithWord: path.startsWithWord,
                    pendingKana: path.pendingKana + String(characters[index]),
                    validConnectors: path.validConnectors
                ))
                for match in matches[index] {
                    push(match.end, Path(
                        text: path.text + match.value,
                        score: path.score + match.score,
                        words: path.words + 1,
                        registeredWords: path.registeredWords + (match.registered ? 1 : 0),
                        startsWithWord: path.startsWithWord || (index == 0 && path.words == 0),
                        pendingKana: "",
                        validConnectors: path.validConnectors &&
                            isCombinationConnector(path.pendingKana)
                    ))
                }
            }
        }
        var seen = Set<String>()
        return Array(beams.last!.sorted { $0.score > $1.score }
            .filter { $0.words >= 2 && $0.registeredWords >= minimumRegisteredWords &&
                $0.text != reading &&
                (!requireBoundaryMatches || ($0.startsWithWord && $0.validConnectors &&
                    isCombinationConnector($0.pendingKana))) }
            .map(\.text)
            .filter { seen.insert($0).inserted }
            .prefix(limit))
    }

    private func canContinueEmailComposition(_ value: String) -> Bool {
        if value == "@", !composing.contains("@") {
            return composing.range(of: #"^[A-Za-z0-9._+\-]*$"#, options: .regularExpression) != nil
        }
        return composing.contains("@") && !value.isEmpty && value.unicodeScalars.allSatisfy {
            (0x41 ... 0x5a).contains($0.value) || (0x61 ... 0x7a).contains($0.value)
                || (0x30 ... 0x39).contains($0.value) || $0.value == 0x2e || $0.value == 0x2d
        }
    }

    private func emailAddressCandidates(_ input: String) -> [String] {
        guard let at = input.lastIndex(of: "@") else { return [] }
        let local = String(input[..<at])
        guard local.range(of: #"^[A-Za-z0-9._+\-]*$"#, options: .regularExpression) != nil else { return [] }
        let prefix = input[at...].lowercased()
        return Self.emailDomains.filter { $0.hasPrefix(prefix) }.map { local + $0 }
    }

    private func buildEnglishCandidates(_ input: String) -> [String] {
        let prefix = input.lowercased()
        var preferred: [String] = []
        for entry in state["userDictionary"] as? [[String: Any]] ?? [] {
            let ruby = entry["ruby"] as? String ?? ""
            let value: String
            if entry["isTemplateMode"] as? Bool == true {
                value = renderTemplate(entry["formatLiteral"] as? String ?? entry["word"] as? String ?? "")
            } else {
                value = entry["word"] as? String ?? ""
            }
            if ruby.lowercased().hasPrefix(prefix) || value.lowercased().hasPrefix(prefix) {
                preferred.append(value)
            }
        }
        for (ruby, values) in osLexicon
            where ruby.lowercased().hasPrefix(prefix) {
            preferred.append(contentsOf: values)
        }

        let learned = learnedCandidateEntries(learningScores(), english: true)
            .filter { $0.reading.hasPrefix(prefix) || $0.text.lowercased().hasPrefix(prefix) }
            .sorted { $0.score > $1.score }
        var result: [String] = []
        var seen = Set<String>()
        func append(_ candidate: String) {
            guard !candidate.isEmpty else { return }
            let matched = matchEnglishCandidateCase(candidate, input: input)
            if seen.insert(matched).inserted { result.append(matched) }
        }
        preferred.forEach(append)
        learned.map(\.text).forEach(append)
        append(input)
        for email in emailAddressCandidates(input) where seen.insert(email).inserted {
            result.append(email)
        }
        Self.englishPredictionWords
            .filter { $0.count > prefix.count && $0.hasPrefix(prefix) }
            .forEach(append)
        return Array(result.prefix(32))
    }

    private func matchEnglishCandidateCase(_ candidate: String, input: String) -> String {
        if input == input.uppercased(), input != input.lowercased() {
            return candidate.uppercased()
        }
        if input.first?.isUppercase == true {
            return candidate.prefix(1).uppercased() + String(candidate.dropFirst())
        }
        return candidate
    }

    private func learningScores() -> [String: Any] {
        guard intSetting("memory_learining_styple_setting", fallback: 0) != 2 else { return [:] }
        return state["learning"] as? [String: Any] ?? [:]
    }

    private func effectiveLearningMode() -> Int {
        if boolSetting("stop_learning_when_search", fallback: false),
           textDocumentProxy.keyboardType == .webSearch || textDocumentProxy.returnKeyType == .search {
            return 2
        }
        return intSetting("memory_learining_styple_setting", fallback: 0)
    }

    private func learnCandidate(input: String, candidate: String, english: Bool, explicitSelection: Bool) {
        guard effectiveLearningMode() == 0 else { return }
        if !english, unknownPredictionTexts.contains(candidate) { return }
        let learningReading = english ? input : (candidatePredictionReadings[candidate] ?? input)
        state["learning"] = recordCandidateLearning(
            learningScores(), reading: learningReading, text: candidate,
            english: english, explicitSelection: explicitSelection
        )
        saveState()
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
        candidateStack.addArrangedSubview(makeCandidateButton("共有辞書へ改善を送信", action: submitPendingReport))
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
        candidateStack.addArrangedSubview(makeCandidateButton("改善を送信", action: submitPendingReport))
        candidateStack.addArrangedSubview(makeCandidateButton("戻る") { [weak self] in self?.showReportPrompt(report) })
    }

    private func showLegacyReportPrompt(_ candidate: String, index: Int) {
        setCandidateExpanded(false)
        candidateExpandButton.isHidden = true
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

    private func showCandidatePreview(_ candidate: String, index: Int) {
        setCandidateExpanded(true)
        candidateExpandButton.isHidden = true
        candidateGrid.removeAllArrangedSubviews()
        let enlarged = UILabel()
        enlarged.text = candidate
        enlarged.font = .systemFont(ofSize: 42)
        enlarged.textColor = palette.text
        enlarged.textAlignment = .center
        enlarged.numberOfLines = 0
        enlarged.lineBreakMode = .byCharWrapping
        enlarged.accessibilityLabel = "拡大した変換候補: \(candidate)"
        enlarged.heightAnchor.constraint(greaterThanOrEqualToConstant: 168).isActive = true
        candidateGrid.addArrangedSubview(enlarged)
        candidateStack.removeAllArrangedSubviews()
        candidateStack.addArrangedSubview(makeCandidateButton("戻る") { [weak self] in self?.renderCandidates(showTabs: false) })
        candidateStack.addArrangedSubview(makeCandidateButton("誤変換を報告") { [weak self] in
            self?.showLegacyReportPrompt(candidate, index: index)
        })
    }

    private func submitPendingReport() {
        guard let report = pendingReport else { return }
        candidateStack.removeAllArrangedSubviews()
        candidateStack.addArrangedSubview(makeCandidateButton("送信中…", action: {}))
        ReportClient.submitSharedConversionImprovement(
            endpoint: UserDefaults(suiteName: "group.com.azooKey.keyboard")?
                .string(forKey: "keynako_dictionary_submission_url") ?? "",
            report: report,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown Version"
        ) { [weak self] success in
            DispatchQueue.main.async {
                guard let self else { return }
                if success { self.registerReportedPair(report) }
                self.pendingReport = nil
                self.candidateStack.removeAllArrangedSubviews()
                self.candidateStack.addArrangedSubview(self.makeCandidateButton(success ? "変換の改善を送信しました" : "送信に失敗しました", action: {}))
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
        setCandidateExpanded(false)
        candidateExpandButton.isHidden = true
        candidateStack.removeAllArrangedSubviews()
        candidateScroll.setContentOffset(.zero, animated: false)
        candidateStack.addArrangedSubview(makeCandidateButton("閉じる") { [weak self] in self?.renderCandidates() })
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
        conversionEngine?.stopComposition()
        selectedCandidateText = nil
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

    private func makeButton(
        _ title: String,
        special: Bool = false,
        quickWordDelete: Bool = false,
        action: @escaping () -> Void
    ) -> UIButton {
        if title == "⌫" {
            let deleteButton = RepeatDeleteButton(
                tap: { [weak self] in
                    if quickWordDelete { self?.quickDelete() } else { action() }
                    self?.feedback()
                },
                repeatAction: { [weak self] in action(); self?.feedback() },
                dragDelete: { [weak self] count in
                    for _ in 0 ..< count { action() }
                    self?.feedback()
                }
            )
            deleteButton.setTitle(title, for: .normal)
            style(deleteButton, special: special)
            return deleteButton
        }
        if title == "space" || title == "空白" || title == "次候補" {
            let cursorDrag: ((Int) -> Void)? = title == "次候補" ? nil : { [weak self] count in
                self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: count)
                self?.refreshCursorBar()
            }
            let spaceButton = RepeatActionButton(
                action: { [weak self] in action(); self?.feedback() },
                longPress: { [weak self] in
                    guard let self else { return }
                    if candidates.isEmpty {
                        if !cursorBarVisible { toggleCursorBar() }
                    } else {
                        selectNextCandidate()
                    }
                },
                dragCursor: cursorDrag
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
        button.backgroundColor = palette.key
        button.layer.cornerRadius = 6
        button.titleLabel?.font = .systemFont(ofSize: CGFloat(doubleSetting("result_view_font_size", fallback: 16).positiveOr(16)))
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)
        return button
    }

    private func makeTabButton(_ title: String, action: @escaping () -> Void) -> ClosureButton {
        let button = makeCandidateButton(title, action: action)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
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
        "かめんらいだー": ["仮面ライダー"],
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
    private static let emojiDictionary = [
        "えがお": ["😊", "😄", "🙂"], "はーと": ["❤️", "💕", "💙"], "ほし": ["⭐️", "🌟", "✨"],
        "ごきぶり": ["🪳"], "か": ["🦟"], "くも": ["🕷️", "🕸️"], "みみず": ["🪱"],
    ]
    private static let kaomojiDictionary = ["えがお": ["( ´ ▽ ` )", "(^_^)"], "かなしい": ["( ; _ ; )", "(´；ω；`)"]]
    private static let emailDomains = [
        "@gmail.com", "@icloud.com", "@yahoo.co.jp", "@au.com",
        "@docomo.ne.jp", "@excite.co.jp", "@ezweb.ne.jp", "@googlemail.com",
        "@hotmail.co.jp", "@hotmail.com", "@i.softbank.jp", "@live.jp",
        "@me.com", "@mineo.jp", "@nifty.com", "@outlook.com", "@outlook.jp",
        "@softbank.ne.jp", "@yahoo.ne.jp", "@ybb.ne.jp", "@ymobile.ne.jp",
    ]
    private static let englishPredictionWords = [
        "a", "about", "after", "again", "all", "also", "always", "am", "an", "and", "any", "are",
        "as", "at", "be", "because", "been", "before", "being", "best", "but", "by", "can", "come",
        "could", "day", "did", "do", "does", "doing", "done", "down", "each", "even", "first", "for",
        "from", "get", "give", "go", "good", "great", "had", "has", "have", "he", "hello", "help",
        "her", "here", "him", "his", "how", "i", "if", "in", "into", "is", "it", "its", "just",
        "know", "like", "look", "love", "make", "me", "more", "most", "my", "need", "new", "no",
        "not", "now", "of", "ok", "okay", "on", "one", "only", "or", "other", "our", "out", "over",
        "people", "please", "really", "right", "said", "same", "see", "she", "should", "so", "some",
        "sorry", "still", "take", "thank", "thanks", "that", "the", "their", "them", "then", "there",
        "these", "they", "thing", "think", "this", "time", "to", "today", "too", "up", "us", "use",
        "very", "want", "was", "way", "we", "well", "were", "what", "when", "where", "which", "who",
        "why", "will", "with", "work", "would", "yes", "you", "your",
    ]
    private static let defaultScanTargets = [
        " ", "　", "\t", "、", "。", "！", "？", ".", ",", "．", "，", "\n",
    ]
    private static func isReportableInput(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3041 ... 0x3096, 0x30 ... 0x39, 0x41 ... 0x5a, 0x61 ... 0x7a: true
        default: false
        }
    }
    private let kanaCharacterForms = [
        "あ": "ぁ", "ぁ": "あ", "い": "ぃ", "ぃ": "い",
        "う": "ぅ", "ぅ": "ゔ", "ゔ": "う", "え": "ぇ", "ぇ": "え",
        "お": "ぉ", "ぉ": "お", "つ": "っ", "っ": "づ", "づ": "つ",
        "や": "ゃ", "ゃ": "や", "ゆ": "ゅ", "ゅ": "ゆ", "よ": "ょ", "ょ": "よ",
        "わ": "ゎ", "ゎ": "わ",
        "か": "が", "が": "か", "き": "ぎ", "ぎ": "き", "く": "ぐ", "ぐ": "く",
        "け": "げ", "げ": "け", "こ": "ご", "ご": "こ",
        "さ": "ざ", "ざ": "さ", "し": "じ", "じ": "し", "す": "ず", "ず": "す",
        "せ": "ぜ", "ぜ": "せ", "そ": "ぞ", "ぞ": "そ",
        "た": "だ", "だ": "た", "ち": "ぢ", "ぢ": "ち", "て": "で", "で": "て",
        "と": "ど", "ど": "と",
        "は": "ば", "ば": "ぱ", "ぱ": "は",
        "ひ": "び", "び": "ぴ", "ぴ": "ひ",
        "ふ": "ぶ", "ぶ": "ぷ", "ぷ": "ふ",
        "へ": "べ", "べ": "ぺ", "ぺ": "へ",
        "ほ": "ぼ", "ぼ": "ぽ", "ぽ": "ほ",
        "ア": "ァ", "ァ": "ア", "イ": "ィ", "ィ": "イ",
        "ウ": "ゥ", "ゥ": "ヴ", "ヴ": "ウ", "エ": "ェ", "ェ": "エ",
        "オ": "ォ", "ォ": "オ", "ツ": "ッ", "ッ": "ヅ", "ヅ": "ツ",
        "ヤ": "ャ", "ャ": "ヤ", "ユ": "ュ", "ュ": "ユ", "ヨ": "ョ", "ョ": "ヨ",
        "ワ": "ヮ", "ヮ": "ワ",
        "カ": "ガ", "ガ": "カ", "キ": "ギ", "ギ": "キ", "ク": "グ", "グ": "ク",
        "ケ": "ゲ", "ゲ": "ケ", "コ": "ゴ", "ゴ": "コ",
        "サ": "ザ", "ザ": "サ", "シ": "ジ", "ジ": "シ", "ス": "ズ", "ズ": "ス",
        "セ": "ゼ", "ゼ": "セ", "ソ": "ゾ", "ゾ": "ソ",
        "タ": "ダ", "ダ": "タ", "チ": "ヂ", "ヂ": "チ", "テ": "デ", "デ": "テ",
        "ト": "ド", "ド": "ト",
        "ハ": "バ", "バ": "パ", "パ": "ハ",
        "ヒ": "ビ", "ビ": "ピ", "ピ": "ヒ",
        "フ": "ブ", "ブ": "プ", "プ": "フ",
        "ヘ": "ベ", "ベ": "ペ", "ペ": "ヘ",
        "ホ": "ボ", "ボ": "ポ", "ポ": "ホ",
    ]
}

private struct NumericKey {
    let label: String
    let input: String?
    let action: String?
    let special: Bool

    init(
        _ label: String = "",
        input: String? = nil,
        action: String? = nil,
        special: Bool = false
    ) {
        self.label = label
        self.input = input
        self.action = action
        self.special = special
    }
}

private func punctuationForInputMode(_ value: String, mode: String) -> String {
    switch mode {
    case "japanese":
        return value.replacingOccurrences(of: "?", with: "？")
            .replacingOccurrences(of: "!", with: "！")
    case "english":
        return value.replacingOccurrences(of: "？", with: "?")
            .replacingOccurrences(of: "！", with: "!")
    default:
        return value
    }
}

private func closingDelimiter(for value: String) -> String? {
    switch value {
    case "「": return "」"
    case "『": return "』"
    case "(": return ")"
    case "（": return "）"
    case "[": return "]"
    case "［": return "］"
    case "{": return "}"
    case "｛": return "｝"
    case "【": return "】"
    case "〈": return "〉"
    case "《": return "》"
    default: return nil
    }
}

private struct DefaultSymbolKey {
    let halfWidth: String
    let fullWidth: String

    init(_ halfWidth: String, _ fullWidth: String) {
        self.halfWidth = halfWidth
        self.fullWidth = fullWidth
    }
}

private let defaultSymbolKeyboardRows = [
    [
        DefaultSymbolKey("1", "１"), DefaultSymbolKey("2", "２"),
        DefaultSymbolKey("3", "３"), DefaultSymbolKey("4", "４"),
        DefaultSymbolKey("5", "５"), DefaultSymbolKey("6", "６"),
        DefaultSymbolKey("7", "７"), DefaultSymbolKey("8", "８"),
        DefaultSymbolKey("9", "９"), DefaultSymbolKey("0", "０"),
    ],
    [
        DefaultSymbolKey("-", "－"), DefaultSymbolKey("/", "／"),
        DefaultSymbolKey(":", "："), DefaultSymbolKey(";", "；"),
        DefaultSymbolKey("(", "（"), DefaultSymbolKey(")", "）"),
        DefaultSymbolKey("¥", "￥"), DefaultSymbolKey("&", "＆"),
        DefaultSymbolKey("@", "＠"), DefaultSymbolKey("\"", "＂"),
    ],
    [
        DefaultSymbolKey("｡", "。"), DefaultSymbolKey("､", "、"),
        DefaultSymbolKey("?", "？"), DefaultSymbolKey("!", "！"),
        DefaultSymbolKey("...", "…"), DefaultSymbolKey("･", "・"),
        DefaultSymbolKey("~", "〜"), DefaultSymbolKey("#", "＃"),
        DefaultSymbolKey("%", "％"),
    ],
]

/// Keeps the source image's pixel dimensions out of the keyboard's Auto Layout size.
private final class KeyboardBackgroundImageView: UIImageView {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
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

private struct PendingQuickWordDelete {
    let deadline: CFTimeInterval
    let composition: Bool
    var expectedComposing = ""
    var expectedRawRoman = ""
    var targetComposing = ""
    var targetRawRoman = ""
    var expectedContext = ""
    var remainingContextCount = 0
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

    static func space(_ label: String, pasteOnCursorKey: Bool = false) -> Self {
        Self(label: label, values: [label, "←", pasteOnCursorKey ? "貼付" : "　", "", "\t"], action: "space", customTarget: nil)
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
    private let reflectStyle: Bool
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
        reflectStyle: Bool,
        fontSize: CGFloat,
        onMove: @escaping (Int) -> Void
    ) {
        self.palette = palette
        self.reflectStyle = reflectStyle
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
        if !reflectStyle {
            palette.key.setFill()
            context.fill(bounds)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 17),
                .foregroundColor: palette.text,
            ]
            ("‹‹" as NSString).draw(at: CGPoint(x: 12, y: bounds.midY - 11), withAttributes: attributes)
            let label = "カーソルを移動" as NSString
            let labelWidth = label.size(withAttributes: attributes).width
            label.draw(at: CGPoint(x: bounds.midX - labelWidth / 2, y: bounds.midY - 11), withAttributes: attributes)
            ("››" as NSString).draw(at: CGPoint(x: bounds.width - 35, y: bounds.midY - 11), withAttributes: attributes)
            return
        }
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
    private let tap: () -> Void
    private let repeatAction: () -> Void
    private let dragDelete: (Int) -> Void
    private var longPressWorkItem: DispatchWorkItem?
    private var repeatTimer: Timer?
    private var didLongPress = false
    private var dragStarted = false
    private var dragCount = 0
    private var startX: CGFloat = 0

    init(tap: @escaping () -> Void, repeatAction: @escaping () -> Void, dragDelete: @escaping (Int) -> Void) {
        self.tap = tap
        self.repeatAction = repeatAction
        self.dragDelete = dragDelete
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        didLongPress = false
        dragStarted = false
        dragCount = 0
        startX = touches.first?.location(in: self).x ?? 0
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.didLongPress = true
            self.repeatAction()
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
                self?.repeatAction()
            }
            self.repeatTimer?.fire()
        }
        longPressWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let x = touches.first?.location(in: self).x ?? startX
        let distance = startX - x
        if dragStarted || distance >= 20 {
            dragStarted = true
            longPressWorkItem?.cancel()
            repeatTimer?.invalidate()
            repeatTimer = nil
            dragCount = min(100, max(0, Int((distance / 18).rounded())))
            setTitle(dragCount == 0 ? "⌫" : "⌫ \(dragCount)", for: .normal)
            accessibilityLabel = "\(dragCount)文字を削除"
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressWorkItem?.cancel()
        repeatTimer?.invalidate()
        repeatTimer = nil
        super.touchesEnded(touches, with: event)
        setTitle("⌫", for: .normal)
        if dragStarted {
            if dragCount > 0 { dragDelete(dragCount) }
        } else if !didLongPress { tap() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressWorkItem?.cancel()
        repeatTimer?.invalidate()
        repeatTimer = nil
        setTitle("⌫", for: .normal)
        super.touchesCancelled(touches, with: event)
    }
}

private final class RepeatActionButton: UIButton {
    private let press: () -> Void
    private let longPress: () -> Void
    private let dragCursor: ((Int) -> Void)?
    private var longPressWorkItem: DispatchWorkItem?
    private var repeatTimer: Timer?
    private var didLongPress = false
    private var cursorDragging = false
    private var startX: CGFloat = 0
    private var dragStep = 0

    init(action: @escaping () -> Void, longPress: @escaping () -> Void, dragCursor: ((Int) -> Void)? = nil) {
        self.press = action
        self.longPress = longPress
        self.dragCursor = dragCursor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        didLongPress = false
        cursorDragging = false
        dragStep = 0
        startX = touches.first?.location(in: self).x ?? 0
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

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if didLongPress, let dragCursor {
            let x = touches.first?.location(in: self).x ?? startX
            let step = Int(((x - startX) / 18).rounded())
            if step != dragStep {
                dragCursor(step - dragStep)
                dragStep = step
                cursorDragging = true
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressWorkItem?.cancel()
        repeatTimer?.invalidate()
        repeatTimer = nil
        super.touchesEnded(touches, with: event)
        if !didLongPress && !cursorDragging { press() }
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
    private var cursorDragging = false
    private var cursorDragStep = 0
    private var deleteDragging = false
    private var deleteDragCount = 0

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
        cursorDragging = false
        cursorDragStep = 0
        deleteDragging = false
        deleteDragCount = 0
        guard definition.action == "delete" || definition.action == "space" || definition.action == "upperLowerEnglish" else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.didLongPress = true
            if self.definition.action == "upperLowerEnglish" {
                self.callback("__capslock__")
            } else if self.definition.action == "delete" {
                self.callback("__delete_repeat__")
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
                    self?.callback("__delete_repeat__")
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
        if deleteDragging {
            setTitle(definition.label, for: .normal)
            if deleteDragCount > 0 { callback("__delete_drag__:\(deleteDragCount)") }
            return
        }
        guard (!didLongPress || longPressFlicked) && !cursorLongPressed && !cursorDragging else { return }
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
        setTitle(definition.label, for: .normal)
        super.touchesCancelled(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        let dx = point.x - start.x
        let dy = point.y - start.y
        if definition.action == "delete", didLongPress {
            let count = min(100, max(0, Int((-dx / 18).rounded())))
            if deleteDragging || count > 0 {
                deleteDragging = true
                deleteDragCount = count
                repeatTimer?.invalidate()
                repeatTimer = nil
                setTitle(count == 0 ? definition.label : "⌫ \(count)", for: .normal)
            }
            return
        }
        if definition.action == "space", didLongPress {
            let step = Int((dx / 18).rounded())
            if step != cursorDragStep {
                repeatTimer?.invalidate()
                repeatTimer = nil
                callback("__cursor_drag__:\(step - cursorDragStep)")
                cursorDragStep = step
                cursorDragging = true
            }
            return
        }
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
    private let callback: ([String: Any]?, Bool) -> Void
    private var start = CGPoint.zero
    private var longPressWorkItem: DispatchWorkItem?
    private var repeatTimer: Timer?
    private var didLongPress = false
    private var longPressFlicked = false

    init(
        key: [String: Any],
        title: String,
        directionTitles: [String: String],
        sensitivity: CGFloat,
        callback: @escaping ([String: Any]?, Bool) -> Void
    ) {
        self.key = key
        self.sensitivity = sensitivity
        self.callback = callback
        super.init(
            title: title,
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
            callback(action, false)
            if let repeated {
                repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
                    self?.callback(repeated, false)
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
        callback(
            key[direction] as? [String: Any] ?? key["tap"] as? [String: Any],
            true
        )
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
    private let makeCenterLongPressRollback: ([[String: Any]], [[String: Any]]) -> (() -> Void)?
    private let callback: ([[String: Any]], Bool) -> Void
    private var start = CGPoint.zero
    private var current = CGPoint.zero
    private var longPressWorkItem: DispatchWorkItem?
    private var repeatTimer: Timer?
    private var didLongPress = false
    private var repeatedLongPress = false
    private var longPressFlicked = false
    private var variationDidLongPress = false
    private var longPressDirection: String?
    private var centerLongPressRollback: (() -> Void)?
    private var continueDeleteVariationOnRelease = false

    init(
        title: String,
        directionTitles: [String: String],
        key: [String: Any],
        keyStyle: String,
        variationsEnabled: Bool,
        sensitivity: CGFloat,
        makeCenterLongPressRollback: @escaping ([[String: Any]], [[String: Any]]) -> (() -> Void)?,
        callback: @escaping ([[String: Any]], Bool) -> Void
    ) {
        self.key = key
        self.keyStyle = keyStyle
        self.variationsEnabled = variationsEnabled
        self.sensitivity = sensitivity
        self.makeCenterLongPressRollback = makeCenterLongPressRollback
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
        centerLongPressRollback = nil
        continueDeleteVariationOnRelease = false
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
            if self.longPressDirection == nil {
                self.centerLongPressRollback = self.makeCenterLongPressRollback(selectedStart, selectedRepeat)
            } else {
                self.centerLongPressRollback = nil
            }
            self.didLongPress = true
            self.variationDidLongPress = self.longPressDirection != nil
            self.repeatedLongPress = !selectedRepeat.isEmpty
            self.callback(selectedStart, false)
            if !selectedRepeat.isEmpty {
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
                    self?.callback(selectedRepeat, false)
                }
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
            let direction: String = abs(dx) > abs(dy) ? (dx < 0 ? "left" : "right") : (dy < 0 ? "top" : "bottom")
            if direction != longPressDirection, variationsEnabled, keyStyle != "pc_style" {
                let variation = variations(type: "flick_variation").first { $0["direction"] as? String == direction }
                let variationKey = variation?["key"] as? [String: Any] ?? [:]
                let variationPressActions = variationKey["press_actions"] as? [[String: Any]] ?? []
                let canContinueAfterDelete = canContinueDeleteLongPress(
                    into: variationPressActions
                )
                if didLongPress, !variationDidLongPress,
                   centerLongPressRollback == nil, !canContinueAfterDelete {
                    // A non-input center action cannot be reversed safely. Keep
                    // that result instead of firing a second variation action.
                    super.touchesMoved(touches, with: event)
                    return
                }
                // Keep the selected variation's timer alive while the finger
                // jitters within the same flick direction.
                longPressWorkItem?.cancel()
                if didLongPress {
                    centerLongPressRollback?()
                    continueDeleteVariationOnRelease =
                        centerLongPressRollback == nil && canContinueAfterDelete
                    centerLongPressRollback = nil
                    longPressFlicked = true
                    didLongPress = false
                    variationDidLongPress = false
                    repeatTimer?.invalidate()
                    repeatTimer = nil
                }
                longPressDirection = direction
                let variationLongPress = variationKey["longpress_actions"] as? [String: Any] ?? [:]
                let startActions = variationLongPress["start"] as? [[String: Any]] ?? []
                let repeatActions = variationLongPress["repeat"] as? [[String: Any]] ?? []
                if !startActions.isEmpty || !repeatActions.isEmpty {
                    let work = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        self.variationDidLongPress = true
                        self.didLongPress = true
                        self.repeatedLongPress = !repeatActions.isEmpty
                        self.callback(startActions, false)
                        if !repeatActions.isEmpty {
                            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in self?.callback(repeatActions, false) }
                        }
                    }
                    longPressWorkItem = work
                    let delay = variationLongPress["duration"] as? String == "light" ? 0.125 : 0.4
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                }
            } else if keyStyle == "pc_style" || !variationsEnabled {
                longPressWorkItem?.cancel()
                if didLongPress {
                    longPressFlicked = true
                    didLongPress = false
                    variationDidLongPress = false
                    repeatTimer?.invalidate()
                    repeatTimer = nil
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
        centerLongPressRollback = nil
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
                    callback(
                        variationKey?["press_actions"] as? [[String: Any]] ?? [],
                        true
                    )
                }
            }
            return
        }
        if longPressFlicked && variationDidLongPress { return }
        let continuedVariation: [String: Any]?
        if continueDeleteVariationOnRelease, let longPressDirection {
            let variation = variations(type: "flick_variation").first {
                $0["direction"] as? String == longPressDirection
            }
            continuedVariation = variation?["key"] as? [String: Any]
        } else {
            continuedVariation = nil
        }
        let selected = continuedVariation ?? selectedGestureKey(at: end)
        let actions = selected["press_actions"] as? [[String: Any]] ?? []
        if continueDeleteVariationOnRelease,
           let startIndex = backwardWordDeleteContinuationStartIndex(actions) {
            callback(Array(actions.dropFirst(startIndex)), true)
        } else {
            callback(actions, true)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressWorkItem?.cancel()
        repeatTimer?.invalidate()
        repeatTimer = nil
        centerLongPressRollback = nil
        super.touchesCancelled(touches, with: event)
    }

    private func variations(type: String) -> [[String: Any]] {
        (key["variations"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == type }
    }

    private func positiveBackwardDelete(_ action: [String: Any]) -> Bool {
        guard action["type"] as? String == "delete" else { return false }
        let count = (action["count"] as? NSNumber)?.intValue
            ?? Int(action["value"] as? String ?? "")
            ?? 1
        return count > 0
    }

    private func backwardWordDeleteContinuationStartIndex(
        _ actions: [[String: Any]]
    ) -> Int? {
        if isBackwardSmartDelete(actions.first) {
            return 0
        }
        guard actions.count >= 2,
              positiveBackwardDelete(actions[0]),
              isBackwardSmartDelete(actions[1]) else { return nil }
        return 1
    }

    private func isBackwardSmartDelete(_ action: [String: Any]?) -> Bool {
        guard let action else { return false }
        switch action["type"] as? String {
        case "smart_delete_default", "smartDeleteDefault": return true
        case "smart_delete": return action["direction"] as? String == "backward"
        default: return false
        }
    }

    private func canContinueDeleteLongPress(into variationActions: [[String: Any]]) -> Bool {
        guard backwardWordDeleteContinuationStartIndex(variationActions) != nil else { return false }
        let longPress = key["longpress_actions"] as? [String: Any] ?? [:]
        let centerActions =
            (longPress["start"] as? [[String: Any]] ?? []) +
            (longPress["repeat"] as? [[String: Any]] ?? [])
        return !centerActions.isEmpty && centerActions.allSatisfy(positiveBackwardDelete)
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
    let backgroundImage: String?
    let backgroundImageRevision: Int64?

    static let light = KeyboardPalette(background: UIColor(argb: 0xffd1d5db), key: .white, special: UIColor(argb: 0xffadb5bd), text: UIColor(argb: 0xff111827), accent: UIColor(argb: 0xff2563eb), backgroundImage: nil, backgroundImageRevision: nil)
    static let dark = KeyboardPalette(background: UIColor(argb: 0xff111827), key: UIColor(argb: 0xff374151), special: UIColor(argb: 0xff1f2937), text: .white, accent: UIColor(argb: 0xff60a5fa), backgroundImage: nil, backgroundImageRevision: nil)
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

// Uses the same bounded correction scores as the Kotlin and Dart converters.
private struct LearnedCandidateEntry {
    let key: String
    let reading: String
    let text: String
    let score: Int
}

private func learnedCandidateEntries(_ learning: [String: Any], english: Bool) -> [LearnedCandidateEntry] {
    learning.compactMap { key, raw -> LearnedCandidateEntry? in
        guard let separator = key.firstIndex(of: "\t") else { return nil }
        var reading = String(key[..<separator])
        let text = String(key[key.index(after: separator)...])
        let count = (raw as? NSNumber)?.intValue ?? (raw as? Int ?? 0)
        guard count > 0, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if reading.hasPrefix("english:") {
            guard english else { return nil }
            reading = String(reading.dropFirst("english:".count))
        } else if english, reading.range(of: "^[a-zA-Z']+$", options: .regularExpression) == nil {
            return nil
        }
        guard !reading.isEmpty else { return nil }
        return LearnedCandidateEntry(
            key: key, reading: english ? reading.lowercased() : katakanaToHiragana(reading),
            text: text, score: min(count, 32)
        )
    }.sorted { $0.key < $1.key }
}

private func recordCandidateLearning(
    _ learning: [String: Any], reading: String, text: String,
    english: Bool, explicitSelection: Bool
) -> [String: Any] {
    guard !reading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !reading.contains("\t"), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return learning }
    let normalized = english ? reading.lowercased() : katakanaToHiragana(reading)
    var result = learning
    var scores: [String: Int] = [:]
    for entry in learnedCandidateEntries(learning, english: english) where entry.reading == normalized {
        let word = english && entry.text.lowercased() == text.lowercased() ? text : entry.text
        scores[word] = max(scores[word] ?? 0, entry.score)
        result.removeValue(forKey: entry.key)
    }
    if explicitSelection {
        for word in Array(scores.keys) where word != text { scores[word] = scores[word]! / 2 }
        scores[text] = min((scores.values.max() ?? 0) + 4, 32)
    } else {
        // Automatic acceptance stays weaker than one deliberate correction.
        let existing = scores[text] ?? 0
        scores[text] = existing >= 4 ? existing : min(existing + 1, 3)
    }
    let prefix = english ? "english:\(normalized)" : normalized
    for (word, score) in scores where score > 0 { result["\(prefix)\t\(word)"] = score }
    return result
}
