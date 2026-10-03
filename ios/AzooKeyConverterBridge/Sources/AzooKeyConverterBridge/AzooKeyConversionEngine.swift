import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

public struct AzooKeyHotfixDictionaryEntry: Sendable {
    public init(
        word: String,
        ruby: String,
        wordWeight: Double,
        lcid: Int,
        rcid: Int,
        mid: Int
    ) {
        self.word = word
        self.ruby = ruby
        self.wordWeight = wordWeight
        self.lcid = lcid
        self.rcid = rcid
        self.mid = mid
    }

    public let word: String
    public let ruby: String
    public let wordWeight: Double
    public let lcid: Int
    public let rcid: Int
    public let mid: Int
}

public struct AzooKeyCompletedClause: Sendable {
    public let text: String
    public let reading: String
}

/// A small, stable boundary between the native keyboard and azooKey's pinned
/// conversion engine. The package revision and ZenzaiCPU trait match the Swift
/// application this Flutter port was derived from.
public final class AzooKeyConversionEngine {
    private let converter = KanaKanjiConverter.withDefaultDictionary()
    private let sharedContainerURL: URL
    private let memoryDirectoryURL: URL
    private var lastCandidates: [String: Candidate] = [:]
    public private(set) var predictionTexts = Set<String>()
    public private(set) var baselineTexts: [String] = []
    public private(set) var completedClause: AzooKeyCompletedClause?
    private var hotfixDictionaryVersion: String?
    private var lastCompletionReading = ""
    private var lastCompletionText = ""
    private var lastCompletionClauseReading = ""
    private var stableCompletionCount = 0

    public init(sharedContainerURL: URL) {
        self.sharedContainerURL = sharedContainerURL
        self.memoryDirectoryURL = sharedContainerURL.appendingPathComponent(
            "azookey_flutter_learning",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: memoryDirectoryURL,
            withIntermediateDirectories: true
        )
        converter.setKeyboardLanguage(.ja_JP)
    }

    public func updateHotfixDictionary(
        _ entries: [AzooKeyHotfixDictionaryEntry],
        version: String
    ) {
        guard hotfixDictionaryVersion != version else { return }
        converter.importDynamicUserDictionary(entries.map { entry in
            DicdataElement(
                word: entry.word,
                ruby: Self.toKatakana(entry.ruby),
                lcid: entry.lcid,
                rcid: entry.rcid,
                mid: entry.mid,
                value: PValue(entry.wordWeight)
            )
        })
        hotfixDictionaryVersion = version
        lastCandidates = [:]
        predictionTexts = []
        baselineTexts = []
    }

    public func candidates(
        reading: String,
        rawRoman: String?,
        leftContext: String?,
        rightContext: String?,
        modelURL: URL?,
        inferenceLimit: Int,
        learningMode: Int,
        automaticCompletionStrength: Int,
        englishCandidateInRoman2KanaInput: Bool,
        typographyCandidate: Bool,
        fullWidthRomanCandidate: Bool,
        halfWidthKanaCandidate: Bool,
        unicodeCandidate: Bool,
        appVersion: String
    ) -> [String] {
        guard !reading.isEmpty else {
            lastCandidates = [:]
            predictionTexts = []
            baselineTexts = []
            resetCompletionHistory()
            return []
        }

        var composingText = ComposingText()
        if let rawRoman, !rawRoman.isEmpty {
            composingText.insertAtCursorPosition(rawRoman, inputStyle: .roman2kana)
        } else {
            composingText.insertAtCursorPosition(reading, inputStyle: .direct)
        }

        let zenzaiMode: ConvertRequestOptions.ZenzaiMode
        if let modelURL {
            zenzaiMode = .on(
                weight: modelURL,
                inferenceLimit: inferenceLimit,
                requestRichCandidates: false,
                personalizationMode: nil,
                versionDependentMode: .v3(
                    .init(
                        leftSideContext: leftContext,
                        rightSideContext: rightContext,
                        maxLeftSideContextLength: 20,
                        maxRightSideContextLength: 20,
                        enableAlignmentSeparator: true
                    )
                )
            )
        } else {
            zenzaiMode = .off
        }

        let learningType: LearningType = switch learningMode {
        case 1: .onlyOutput
        case 2: .nothing
        default: .inputAndOutput
        }
        var providers = KanaKanjiConverter.defaultSpecialCandidateProviders
        if !unicodeCandidate {
            providers.removeAll { $0 is UnicodeSpecialCandidateProvider }
        }
        if typographyCandidate {
            providers.append(TypographySpecialCandidateProvider())
        }
        func options(
            for mode: ConvertRequestOptions.ZenzaiMode,
            predictiveInput: Bool
        ) -> ConvertRequestOptions {
            ConvertRequestOptions(
                N_best: 20,
                requireJapanesePrediction: .autoMix,
                requireEnglishPrediction: .disabled,
                keyboardLanguage: .ja_JP,
                englishCandidateInRoman2KanaInput: englishCandidateInRoman2KanaInput,
                fullWidthRomanCandidate: fullWidthRomanCandidate,
                halfWidthKanaCandidate: halfWidthKanaCandidate,
                learningType: learningType,
                maxMemoryCount: learningMode == 2 ? 0 : 65_536,
                memoryDirectoryURL: memoryDirectoryURL,
                sharedContainerURL: sharedContainerURL,
                textReplacer: .withDefaultEmojiDictionary(),
                specialCandidateProviders: providers,
                zenzaiMode: mode,
                experimentalZenzaiPredictiveInput: predictiveInput,
                typoCorrectionMode: .automatic,
                metadata: .init(versionString: "Keynako \(appVersion)")
            )
        }
        // Keep a standard conversion available when model suggestions are unusual.
        let baseline = converter.requestCandidates(
            composingText,
            options: options(for: .off, predictiveInput: false)
        )
        let result = modelURL == nil
            ? baseline
            : converter.requestCandidates(
                composingText,
                options: options(for: zenzaiMode, predictiveInput: true)
            )
        baselineTexts = baseline.mainResults.map(\.text)
        let mainTexts = Set(result.mainResults.map(\.text)).union(baselineTexts)
        predictionTexts = Set(result.predictionResults.map(\.text)).subtracting(mainTexts)
        let values = result.mainResults + baseline.mainResults + result.predictionResults
        lastCandidates = [:]
        var texts: [String] = []
        var seen = Set<String>()
        for candidate in values where !candidate.text.isEmpty && seen.insert(candidate.text).inserted {
            texts.append(candidate.text)
            if lastCandidates[candidate.text] == nil { lastCandidates[candidate.text] = candidate }
        }
        updateCompletionHistory(
            reading: reading,
            firstClauseResults: baseline.firstClauseResults,
            mainText: baseline.mainResults.first?.text,
            strength: automaticCompletionStrength
        )
        return texts
    }

    private func updateCompletionHistory(
        reading: String,
        firstClauseResults: [Candidate],
        mainText: String?,
        strength: Int
    ) {
        completedClause = nil
        let thresholds = [Int.max, 16, 13, 10, 6]
        let threshold = thresholds[max(0, min(strength, 4))]
        guard threshold != .max,
              let mainText,
              let clause = firstClauseResults.first(where: { mainText.hasPrefix($0.text) }),
              !clause.text.isEmpty,
              mainText.count > clause.text.count else {
            resetCompletionHistory()
            return
        }
        let clauseReading = Self.toHiragana(clause.data.map(\.ruby).joined())
        guard clauseReading.count >= 2,
              reading.hasPrefix(clauseReading),
              reading.count > clauseReading.count,
              clause.text != clauseReading else {
            resetCompletionHistory()
            return
        }
        if reading != lastCompletionReading {
            stableCompletionCount = reading.hasPrefix(lastCompletionReading)
                && clause.text == lastCompletionText
                && clauseReading == lastCompletionClauseReading
                ? stableCompletionCount + 1 : 1
            lastCompletionReading = reading
            lastCompletionText = clause.text
            lastCompletionClauseReading = clauseReading
        }
        if stableCompletionCount >= threshold {
            completedClause = .init(text: clause.text, reading: clauseReading)
            lastCandidates[clause.text] = clause
        }
    }

    private func resetCompletionHistory() {
        completedClause = nil
        lastCompletionReading = ""
        lastCompletionText = ""
        lastCompletionClauseReading = ""
        stableCompletionCount = 0
    }

    public func commit(candidateText: String, learningMode: Int) {
        if learningMode == 0, let candidate = lastCandidates[candidateText] {
            converter.updateLearningData(candidate)
            converter.commitUpdateLearningData()
        }
        converter.stopComposition()
        lastCandidates = [:]
        predictionTexts = []
        baselineTexts = []
        resetCompletionHistory()
    }

    public func stopComposition() {
        converter.stopComposition()
        lastCandidates = [:]
        predictionTexts = []
        baselineTexts = []
        resetCompletionHistory()
    }

    public func resetLearning() {
        converter.resetMemory()
        lastCandidates = [:]
        predictionTexts = []
        baselineTexts = []
        resetCompletionHistory()
    }

    private static func toKatakana(_ value: String) -> String {
        String(value.unicodeScalars.map { scalar in
            if (0x3041 ... 0x3096).contains(scalar.value),
               let converted = UnicodeScalar(scalar.value + 0x60) {
                return Character(converted)
            }
            return Character(scalar)
        })
    }

    private static func toHiragana(_ value: String) -> String {
        String(value.unicodeScalars.map { scalar in
            if (0x30A1 ... 0x30F6).contains(scalar.value),
               let converted = UnicodeScalar(scalar.value - 0x60) {
                return Character(converted)
            }
            return Character(scalar)
        })
    }
}
