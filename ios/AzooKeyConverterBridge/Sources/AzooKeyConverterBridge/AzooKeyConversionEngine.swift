import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

/// A small, stable boundary between the native keyboard and azooKey's pinned
/// conversion engine. The package revision and ZenzaiCPU trait match the Swift
/// application this Flutter port was derived from.
public final class AzooKeyConversionEngine {
    private let converter = KanaKanjiConverter.withDefaultDictionary()
    private let sharedContainerURL: URL
    private let memoryDirectoryURL: URL
    private var lastCandidates: [String: Candidate] = [:]

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
}
