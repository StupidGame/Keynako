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

/// A small, stable boundary between the native keyboard and azooKey's pinned
/// conversion engine. The package revision and ZenzaiCPU trait match the Swift
/// application this Flutter port was derived from.
public final class AzooKeyConversionEngine {
    private let converter = KanaKanjiConverter.withDefaultDictionary()
    private let sharedContainerURL: URL
    private let memoryDirectoryURL: URL
    private var lastCandidates: [String: Candidate] = [:]
    private var hotfixDictionaryVersion: String?

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
    }

    public func candidates(
        reading: String,
        rawRoman: String?,
        leftContext: String?,
        rightContext: String?,
        modelURL: URL?,
        inferenceLimit: Int,
        learningMode: Int,
        fullWidthRomanCandidate: Bool,
        halfWidthKanaCandidate: Bool,
        unicodeCandidate: Bool,
        appVersion: String
    ) -> [String] {
        guard !reading.isEmpty else {
            lastCandidates = [:]
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
        let options = ConvertRequestOptions(
            N_best: 20,
            requireJapanesePrediction: .autoMix,
            requireEnglishPrediction: .disabled,
            keyboardLanguage: .ja_JP,
            englishCandidateInRoman2KanaInput: true,
            fullWidthRomanCandidate: fullWidthRomanCandidate,
            halfWidthKanaCandidate: halfWidthKanaCandidate,
            learningType: learningType,
            maxMemoryCount: learningMode == 2 ? 0 : 65_536,
            memoryDirectoryURL: memoryDirectoryURL,
            sharedContainerURL: sharedContainerURL,
            textReplacer: .withDefaultEmojiDictionary(),
            specialCandidateProviders: providers,
            zenzaiMode: zenzaiMode,
            experimentalZenzaiPredictiveInput: modelURL != nil,
            typoCorrectionMode: .automatic,
            metadata: .init(versionString: "Keynako \(appVersion)")
        )
        let result = converter.requestCandidates(composingText, options: options)
        let values = result.mainResults + result.predictionResults
        lastCandidates = [:]
        var texts: [String] = []
        var seen = Set<String>()
        for candidate in values where !candidate.text.isEmpty && seen.insert(candidate.text).inserted {
            texts.append(candidate.text)
            lastCandidates[candidate.text] = candidate
        }
        return texts
    }

    public func commit(candidateText: String, learningMode: Int) {
        if learningMode == 0, let candidate = lastCandidates[candidateText] {
            converter.updateLearningData(candidate)
            converter.commitUpdateLearningData()
        }
        converter.stopComposition()
        lastCandidates = [:]
    }

    public func stopComposition() {
        converter.stopComposition()
        lastCandidates = [:]
    }

    public func resetLearning() {
        converter.resetMemory()
        lastCandidates = [:]
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
}
