import Foundation

public enum KokoroG2PEngine: String, Sendable {
    case misaki
    case eSpeakNG

    public var displayName: String {
        switch self {
        case .misaki:
            return "Misaki"
        case .eSpeakNG:
            return "eSpeakNG"
        }
    }
}

public struct KokoroSynthesisConfig: Sendable {
    public static let defaultVoiceName = "af_heart"
    public static let defaultG2PEngine: KokoroG2PEngine = .misaki
    public static let streamingTargetCharsPerChunk = 220
    public static let maxTokenFallbackDepth = 6
    public static let paragraphPauseSeconds: Double = 0.3
    public static let sampleRate = 24_000

    public let voiceName: String
    public let g2pEngine: KokoroG2PEngine
    public let insertParagraphPause: Bool

    public init(
        voiceName: String = Self.defaultVoiceName,
        g2pEngine: KokoroG2PEngine = Self.defaultG2PEngine,
        insertParagraphPause: Bool = true
    ) {
        self.voiceName = voiceName
        self.g2pEngine = g2pEngine
        self.insertParagraphPause = insertParagraphPause
    }
}

public struct ChunkSynthesisStats: Sendable {
    public var paragraphCount: Int = 0
    public var synthesisCallCount: Int = 0
    public var maxChunkCharCount: Int = 0
    public var sentenceFallbackCount: Int = 0
    public var wordFallbackCount: Int = 0
    public var chunkCount: Int = 0
    public var wallSeconds: Double = 0
    public var mlxPeakMegabytes: Double = 0

    public init() {}
}

public struct LocalSynthesisResult: Sendable {
    public let outputURL: URL
    public let audioDurationSeconds: Double
    public let stats: ChunkSynthesisStats
    public let cacheStatus: String

    public init(
        outputURL: URL,
        audioDurationSeconds: Double,
        stats: ChunkSynthesisStats,
        cacheStatus: String
    ) {
        self.outputURL = outputURL
        self.audioDurationSeconds = audioDurationSeconds
        self.stats = stats
        self.cacheStatus = cacheStatus
    }
}

public enum LocalKokoroError: Error, LocalizedError, Sendable {
    case modelAssetsMissing
    case voiceNotFound(String)
    case synthesisFailed(String)
    case deviceNotSupported(String)
    case scriptEmpty
    case cacheWriteFailed

    public var errorDescription: String? {
        switch self {
        case .modelAssetsMissing:
            return "Kokoro model assets are missing from the app bundle."
        case .voiceNotFound(let voiceName):
            return "Voice \(voiceName) was not found in voices.npz."
        case .synthesisFailed(let message):
            return "On-device synthesis failed: \(message)"
        case .deviceNotSupported(let reason):
            return "On-device audio is not supported on this device: \(reason)"
        case .scriptEmpty:
            return "Story script is empty."
        case .cacheWriteFailed:
            return "Failed to write synthesized audio to disk."
        }
    }
}
