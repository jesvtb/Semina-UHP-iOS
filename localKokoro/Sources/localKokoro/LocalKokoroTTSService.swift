import AVFoundation
import Foundation
import KokoroSwift
import MLX
import MLXUtilsLibrary
#if canImport(UIKit)
import UIKit
#endif

public actor LocalKokoroTTSService {
    public static let shared = LocalKokoroTTSService()

    private var engine: KokoroTTS?
    private var voices: [String: MLXArray] = [:]
    private var config: KokoroSynthesisConfig = KokoroSynthesisConfig()
    private let resourceBundle: Bundle

    public init(resourceBundle: Bundle = .main) {
        self.resourceBundle = resourceBundle
    }

    public func updateConfig(_ newConfig: KokoroSynthesisConfig) throws {
        if config.g2pEngine != newConfig.g2pEngine {
            engine = nil
        }
        config = newConfig
        try ensureEngineLoaded()
    }

    public func synthesizeScript(
        script: String,
        journeyId: String,
        manifestVersion: Int,
        storyId: String
    ) async throws -> LocalSynthesisResult {
        let normalizedScript = script.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedScript.isEmpty {
            throw LocalKokoroError.scriptEmpty
        }
        guard await isGPUWorkAllowedForSynthesis() else {
            throw CancellationError()
        }

        MLXRuntimeBootstrap.configureIfNeeded()
        try ensureEngineLoaded()

        let outputURL = try LocalKokoroCacheKey.localAudioURL(
            journeyId: journeyId,
            manifestVersion: manifestVersion,
            storyId: storyId,
            config: config,
            script: normalizedScript
        )
        if FileManager.default.fileExists(atPath: outputURL.path),
           let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
           let fileSize = attributes[.size] as? NSNumber,
           fileSize.intValue > 0 {
            let durationSeconds = try await audioDurationSeconds(at: outputURL)
            return LocalSynthesisResult(
                outputURL: outputURL,
                audioDurationSeconds: durationSeconds,
                stats: ChunkSynthesisStats(),
                cacheStatus: "hit"
            )
        }

        let startedAt = CFAbsoluteTimeGetCurrent()
        GPU.resetPeakMemory()

        var stats = ChunkSynthesisStats()
        let chunks = KokoroTextChunker.buildStreamingChunks(text: normalizedScript)
        stats.paragraphCount = KokoroTextChunker.breakParagraphs(text: normalizedScript).count
        stats.chunkCount = chunks.count

        guard let kokoroEngine = engine else {
            throw LocalKokoroError.synthesisFailed("Engine is not loaded.")
        }
        let voice = try resolveVoiceArray()
        let language = KokoroTextChunker.resolveLanguage(forVoiceName: config.voiceName)

        var mergedAudio: [Float] = []
        for chunk in chunks {
            try Task.checkCancellation()
            guard await isGPUWorkAllowedForSynthesis() else {
                throw CancellationError()
            }
            let chunkAudio = try autoreleasepool(invoking: {
                try KokoroOverflowFallback.synthesizeTextSegment(
                    text: chunk.text,
                    engine: kokoroEngine,
                    voice: voice,
                    language: language,
                    stats: &stats
                )
            })
            mergedAudio.append(contentsOf: chunkAudio)
            if config.insertParagraphPause, chunk.isParagraphEnding {
                mergedAudio.append(
                    contentsOf: LocalAudioFileWriter.silenceSamples(
                        seconds: KokoroSynthesisConfig.paragraphPauseSeconds
                    )
                )
            }
            GPU.clearCache()
        }

        try await LocalAudioFileWriter.writePCMToM4A(samples: mergedAudio, outputURL: outputURL)

        let mlxMemoryAfter = GPU.snapshot()
        stats.wallSeconds = CFAbsoluteTimeGetCurrent() - startedAt
        stats.mlxPeakMegabytes = Double(mlxMemoryAfter.peakMemory) / (1024 * 1024)

        let durationSeconds = Double(mergedAudio.count) / Double(KokoroSynthesisConfig.sampleRate)
        return LocalSynthesisResult(
            outputURL: outputURL,
            audioDurationSeconds: durationSeconds,
            stats: stats,
            cacheStatus: "miss"
        )
    }

    private func ensureEngineLoaded() throws {
        if engine != nil, !voices.isEmpty {
            return
        }
        guard let modelURL = resourceBundle.url(
            forResource: "kokoro-v1_0",
            withExtension: "safetensors"
        ) else {
            throw LocalKokoroError.modelAssetsMissing
        }
        guard let voicesURL = resourceBundle.url(forResource: "voices", withExtension: "npz") else {
            throw LocalKokoroError.modelAssetsMissing
        }

        let g2p: G2P = config.g2pEngine == .misaki ? .misaki : .eSpeakNG
        engine = KokoroTTS(modelPath: modelURL, g2p: g2p)
        voices = NpyzReader.read(fileFromPath: voicesURL) ?? [:]
        if voices.isEmpty {
            throw LocalKokoroError.modelAssetsMissing
        }
    }

    private func resolveVoiceArray() throws -> MLXArray {
        let voiceKey = config.voiceName + ".npy"
        guard let voiceArray = voices[voiceKey] else {
            throw LocalKokoroError.voiceNotFound(config.voiceName)
        }
        return voiceArray
    }

    private func audioDurationSeconds(at url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : 0
    }

    private func isGPUWorkAllowedForSynthesis() async -> Bool {
        #if canImport(UIKit)
        return await MainActor.run {
            UIApplication.shared.applicationState == .active
        }
        #else
        return true
        #endif
    }
}
