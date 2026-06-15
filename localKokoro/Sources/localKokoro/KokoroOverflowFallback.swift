import Foundation
import KokoroSwift
import MLX

public enum KokoroOverflowFallback {
    public static func synthesizeTextSegment(
        text: String,
        engine: KokoroTTS,
        voice: MLXArray,
        language: Language,
        depth: Int = 0,
        stats: inout ChunkSynthesisStats
    ) throws -> [Float] {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedText.isEmpty {
            return []
        }

        stats.maxChunkCharCount = max(stats.maxChunkCharCount, normalizedText.count)

        do {
            let (audio, _) = try engine.generateAudio(
                voice: voice,
                language: language,
                text: normalizedText
            )
            stats.synthesisCallCount += 1
            return audio
        } catch {
            GPU.clearCache()
            guard KokoroTextChunker.isTooManyTokensError(error),
                  depth < KokoroSynthesisConfig.maxTokenFallbackDepth else {
                throw error
            }

            let sentenceParts = KokoroTextChunker.splitBySentenceBoundaries(text: normalizedText)
            if sentenceParts.count > 1 {
                stats.sentenceFallbackCount += 1
                var merged: [Float] = []
                for part in sentenceParts {
                    let partAudio = try synthesizeTextSegment(
                        text: part,
                        engine: engine,
                        voice: voice,
                        language: language,
                        depth: depth + 1,
                        stats: &stats
                    )
                    merged.append(contentsOf: partAudio)
                }
                return merged
            }

            let wordParts = KokoroTextChunker.splitByWordBoundaries(text: normalizedText)
            if wordParts.count > 1 {
                stats.wordFallbackCount += 1
                var merged: [Float] = []
                for part in wordParts {
                    let partAudio = try synthesizeTextSegment(
                        text: part,
                        engine: engine,
                        voice: voice,
                        language: language,
                        depth: depth + 1,
                        stats: &stats
                    )
                    merged.append(contentsOf: partAudio)
                }
                return merged
            }

            throw error
        }
    }
}
