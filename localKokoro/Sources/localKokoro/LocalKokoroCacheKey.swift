import CryptoKit
import Foundation

public enum LocalKokoroCacheKey {
    public static func artifactFileName(
        journeyId: String,
        manifestVersion: Int,
        storyId: String,
        config: KokoroSynthesisConfig,
        script: String
    ) -> String {
        let digestInput = [
            journeyId,
            String(manifestVersion),
            storyId,
            config.g2pEngine.rawValue,
            config.voiceName,
            script,
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(digestInput.utf8))
        let cacheKey = digest.map { String(format: "%02x", $0) }.joined()
        return "\(storyId)-\(cacheKey.prefix(16)).m4a"
    }

    public static func localAudioURL(
        journeyId: String,
        manifestVersion: Int,
        storyId: String,
        config: KokoroSynthesisConfig,
        script: String
    ) throws -> URL {
        let fileName = artifactFileName(
            journeyId: journeyId,
            manifestVersion: manifestVersion,
            storyId: storyId,
            config: config,
            script: script
        )
        let subdirectory = "journeys/\(journeyId)/local_audio/v\(manifestVersion)"
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let directoryURL = baseURL.appendingPathComponent(subdirectory, isDirectory: true)
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        }
        return directoryURL.appendingPathComponent(fileName)
    }

    public static func invalidateStaleArtifacts(
        journeyId: String,
        manifestVersion: Int
    ) throws {
        let rootDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("journeys/\(journeyId)/local_audio", isDirectory: true)
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else {
            return
        }
        let currentVersionDirectory = "v\(manifestVersion)"
        let childURLs = try FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        )
        for childURL in childURLs where childURL.lastPathComponent != currentVersionDirectory {
            try FileManager.default.removeItem(at: childURL)
        }
    }
}
