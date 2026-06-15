import CryptoKit
import Foundation
import KokoroSwift

public struct KokoroStreamingChunk: Sendable {
    public let text: String
    public let isParagraphEnding: Bool

    public init(text: String, isParagraphEnding: Bool) {
        self.text = text
        self.isParagraphEnding = isParagraphEnding
    }
}

public enum KokoroTextChunker {
    /// Mirrors `02_package/semina/inference/tts_model.py` `_break_paragraphs`.
    public static func breakParagraphs(text: String) -> [String] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            return []
        }

        let rawParagraphs: [String]
        if trimmedText.contains("\n\n") {
            rawParagraphs = trimmedText.components(separatedBy: "\n\n")
        } else {
            rawParagraphs = trimmedText.components(separatedBy: "\n")
        }

        return rawParagraphs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public static func buildStreamingChunks(
        text: String,
        targetCharsPerChunk: Int = KokoroSynthesisConfig.streamingTargetCharsPerChunk
    ) -> [KokoroStreamingChunk] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            return []
        }

        let paragraphs = breakParagraphs(text: trimmedText)
        var chunks: [KokoroStreamingChunk] = []
        for paragraph in paragraphs {
            let sentenceUnits = splitBySentenceBoundaries(text: paragraph)
            let units = sentenceUnits.isEmpty ? [paragraph] : sentenceUnits

            var paragraphChunks: [String] = []
            var currentChunk: [String] = []
            var currentCharCount = 0
            for sentence in units {
                let sentenceLength = sentence.count
                let separatorLength = currentChunk.isEmpty ? 0 : 1
                if currentCharCount + sentenceLength + separatorLength > targetCharsPerChunk,
                   !currentChunk.isEmpty {
                    paragraphChunks.append(currentChunk.joined(separator: " "))
                    currentChunk = [sentence]
                    currentCharCount = sentenceLength
                } else {
                    currentChunk.append(sentence)
                    currentCharCount += sentenceLength + separatorLength
                }
            }
            if !currentChunk.isEmpty {
                paragraphChunks.append(currentChunk.joined(separator: " "))
            }

            for (chunkIndex, chunkText) in paragraphChunks.enumerated() {
                let normalizedText = chunkText.trimmingCharacters(in: .whitespacesAndNewlines)
                if normalizedText.isEmpty {
                    continue
                }
                let isParagraphEnding = chunkIndex == paragraphChunks.count - 1
                chunks.append(
                    KokoroStreamingChunk(
                        text: normalizedText,
                        isParagraphEnding: isParagraphEnding
                    )
                )
            }
        }
        return chunks
    }

    public static func splitBySentenceBoundaries(text: String) -> [String] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty {
            return []
        }

        var sentences: [String] = []
        var current = ""
        for character in trimmedText {
            current.append(character)
            if ".!?".contains(character) {
                let normalized = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    sentences.append(normalized)
                }
                current = ""
            }
        }
        let trailing = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty {
            sentences.append(trailing)
        }
        return sentences.filter { !$0.isEmpty }
    }

    public static func splitByWordBoundaries(text: String) -> [String] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.count <= 1 {
            return [text]
        }
        let midpoint = words.count / 2
        let left = words.prefix(midpoint).joined(separator: " ")
        let right = words.suffix(from: midpoint).joined(separator: " ")
        return [left, right].filter { !$0.isEmpty }
    }

    public static func resolveLanguage(forVoiceName voiceName: String) -> Language {
        voiceName.first == "a" ? .enUS : .enGB
    }

    public static func isTooManyTokensError(_ error: Error) -> Bool {
        if case KokoroTTS.KokoroTTSError.tooManyTokens = error {
            return true
        }
        return false
    }
}
