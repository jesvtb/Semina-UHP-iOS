import Combine
import Foundation

public enum JourneyDownloadState: String, Codable, Sendable {
    case idle
    case downloading
    case downloaded
    case failed
}

public struct DownloadProgress: Sendable {
    public let journeyId: String
    public let completedCount: Int
    public let totalCount: Int
    public let progress: Double

    public init(journeyId: String, completedCount: Int, totalCount: Int, progress: Double) {
        self.journeyId = journeyId
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.progress = progress
    }
}

public enum JourneyManifestDownloaderError: Error, LocalizedError {
    case invalidJourneyId
    case invalidBaseURL
    case invalidManifestResponse
    case missingDownloadURL

    public var errorDescription: String? {
        switch self {
        case .invalidJourneyId:
            return "journeyId is required."
        case .invalidBaseURL:
            return "Journey manifest downloader base URL is invalid."
        case .invalidManifestResponse:
            return "Failed to decode journey manifest response."
        case .missingDownloadURL:
            return "Manifest contains an invalid asset URL."
        }
    }
}

@MainActor
public final class JourneyManifestDownloader: ObservableObject {
    public typealias AccessTokenProvider = @Sendable () async throws -> String

    @Published public private(set) var journeyDownloadStateById: [String: JourneyDownloadState]
    @Published public private(set) var journeyProgressById: [String: Double]

    private let baseURL: String
    private let accessTokenProvider: AccessTokenProvider
    private let urlSession: URLSession
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    private var cancelledJourneyIds: Set<String> = []
    private var downloadProgressContinuation: AsyncStream<DownloadProgress>.Continuation?

    private let downloadedJourneysStorageKey = "journey_manifest.downloaded_journeys"
    private let audioPathMapStorageKey = "journey_manifest.audio_path_map"
    private let materialPathMapStorageKey = "journey_manifest.material_path_map"

    public lazy var downloadProgress: AsyncStream<DownloadProgress> = {
        AsyncStream { continuation in
            self.downloadProgressContinuation = continuation
        }
    }()

    public init(
        baseURL: String,
        accessTokenProvider: @escaping AccessTokenProvider,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL.hasSuffix("/")
            ? String(baseURL.dropLast())
            : baseURL
        self.accessTokenProvider = accessTokenProvider
        self.urlSession = urlSession
        self.journeyDownloadStateById = [:]
        self.journeyProgressById = [:]

        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase

        let downloadedJourneyIds = Set(
            Storage.loadFromUserDefaults(
                forKey: downloadedJourneysStorageKey,
                as: [String].self
            ) ?? []
        )
        for downloadedJourneyId in downloadedJourneyIds {
            journeyDownloadStateById[downloadedJourneyId] = .downloaded
            journeyProgressById[downloadedJourneyId] = 1.0
        }
    }

    public func fetchDownloadManifest(_ journeyId: String) async throws -> DownloadManifest {
        let normalizedJourneyId = journeyId.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedJourneyId.isEmpty {
            throw JourneyManifestDownloaderError.invalidJourneyId
        }

        guard baseURL.hasPrefix("http://") || baseURL.hasPrefix("https://") else {
            throw JourneyManifestDownloaderError.invalidBaseURL
        }

        let token = try await accessTokenProvider()
        guard let manifestURL = URL(string: "\(baseURL)/v1/journeys/\(normalizedJourneyId)/download-manifest") else {
            throw JourneyManifestDownloaderError.invalidBaseURL
        }

        var request = URLRequest(url: manifestURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JourneyManifestDownloaderError.invalidManifestResponse
        }
        if httpResponse.statusCode != 200 {
            throw APIError(
                message: "Manifest request failed with status \(httpResponse.statusCode)",
                code: httpResponse.statusCode
            )
        }

        do {
            return try jsonDecoder.decode(DownloadManifest.self, from: data)
        } catch {
            throw JourneyManifestDownloaderError.invalidManifestResponse
        }
    }

    public func downloadJourney(_ journeyId: String) async throws {
        let normalizedJourneyId = journeyId.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedJourneyId.isEmpty {
            throw JourneyManifestDownloaderError.invalidJourneyId
        }

        cancelledJourneyIds.remove(normalizedJourneyId)
        journeyDownloadStateById[normalizedJourneyId] = .downloading
        journeyProgressById[normalizedJourneyId] = 0
        publishProgress(
            journeyId: normalizedJourneyId,
            completedCount: 0,
            totalCount: 1
        )

        do {
            let manifest = try await fetchDownloadManifest(normalizedJourneyId)
            try saveManifestToDisk(manifest: manifest)

            var audioPathMap = loadPathMap(forKey: audioPathMapStorageKey)
            var materialPathMap = loadPathMap(forKey: materialPathMapStorageKey)

            let assets = try buildDownloadAssets(from: manifest)
            let totalCount = max(assets.count, 1)
            var completedCount = 0
            for asset in assets {
                if cancelledJourneyIds.contains(normalizedJourneyId) {
                    throw CancellationError()
                }
                let (assetData, _) = try await urlSession.data(from: asset.url)
                let localURL = try Storage.saveToApplicationSupport(
                    data: assetData,
                    filename: asset.filename,
                    subdirectory: asset.subdirectory
                )
                if asset.kind == .audio {
                    audioPathMap[asset.assetId] = localURL.path
                } else {
                    materialPathMap[asset.assetId] = localURL.path
                }
                completedCount += 1
                let progress = Double(completedCount) / Double(totalCount)
                journeyProgressById[normalizedJourneyId] = progress
                publishProgress(
                    journeyId: normalizedJourneyId,
                    completedCount: completedCount,
                    totalCount: totalCount
                )
            }

            savePathMap(audioPathMap, forKey: audioPathMapStorageKey)
            savePathMap(materialPathMap, forKey: materialPathMapStorageKey)
            markJourneyDownloaded(normalizedJourneyId)

            journeyDownloadStateById[normalizedJourneyId] = .downloaded
            journeyProgressById[normalizedJourneyId] = 1
        } catch {
            if error is CancellationError {
                journeyDownloadStateById[normalizedJourneyId] = .idle
                journeyProgressById[normalizedJourneyId] = 0
                cancelledJourneyIds.remove(normalizedJourneyId)
                return
            }
            journeyDownloadStateById[normalizedJourneyId] = .failed
            throw error
        }
    }

    public func cancelDownload(journeyId: String) {
        let normalizedJourneyId = journeyId.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedJourneyId.isEmpty {
            return
        }
        cancelledJourneyIds.insert(normalizedJourneyId)
    }

    public func isJourneyDownloaded(journeyId: String) -> Bool {
        let downloadedJourneyIds = Set(
            Storage.loadFromUserDefaults(
                forKey: downloadedJourneysStorageKey,
                as: [String].self
            ) ?? []
        )
        return downloadedJourneyIds.contains(journeyId)
    }

    public func loadManifestFromDisk(journeyId: String) throws -> DownloadManifest? {
        if !Storage.existsInApplicationSupport(
            filename: "manifest.json",
            subdirectory: "journeys/\(journeyId)"
        ) {
            return nil
        }
        let manifestData = try Storage.loadFromApplicationSupport(
            filename: "manifest.json",
            subdirectory: "journeys/\(journeyId)"
        )
        return try jsonDecoder.decode(DownloadManifest.self, from: manifestData)
    }

    public func getLocalAudioURL(storyId: String) -> URL? {
        let audioPathMap = loadPathMap(forKey: audioPathMapStorageKey)
        guard let localPath = audioPathMap[storyId] else { return nil }
        return URL(fileURLWithPath: localPath)
    }

    public func getLocalMaterialURL(materialId: String) -> URL? {
        let materialPathMap = loadPathMap(forKey: materialPathMapStorageKey)
        guard let localPath = materialPathMap[materialId] else { return nil }
        return URL(fileURLWithPath: localPath)
    }

    private enum DownloadAssetKind {
        case audio
        case material
    }

    private struct DownloadAsset {
        let assetId: String
        let kind: DownloadAssetKind
        let url: URL
        let filename: String
        let subdirectory: String
    }

    private func buildDownloadAssets(from manifest: DownloadManifest) throws -> [DownloadAsset] {
        var assets: [DownloadAsset] = []
        for story in manifest.stories {
            guard let audioURL = URL(string: story.audioUrl) else {
                throw JourneyManifestDownloaderError.missingDownloadURL
            }
            let audioExtension = audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension
            assets.append(
                DownloadAsset(
                    assetId: story.storyId,
                    kind: .audio,
                    url: audioURL,
                    filename: "\(story.storyId).\(audioExtension)",
                    subdirectory: "audio"
                )
            )

            for material in story.materials {
                guard let downloadURLString = material.payload["download_url"]?.stringValue else {
                    continue
                }
                guard let materialURL = URL(string: downloadURLString) else {
                    throw JourneyManifestDownloaderError.missingDownloadURL
                }
                let extensionFallback = material.type.isEmpty ? "bin" : material.type
                let materialExtension = materialURL.pathExtension.isEmpty ? extensionFallback : materialURL.pathExtension
                assets.append(
                    DownloadAsset(
                        assetId: material.id,
                        kind: .material,
                        url: materialURL,
                        filename: "\(material.id).\(materialExtension)",
                        subdirectory: "materials"
                    )
                )
            }
        }
        return assets
    }

    private func saveManifestToDisk(manifest: DownloadManifest) throws {
        let manifestData = try jsonEncoder.encode(manifest)
        _ = try Storage.saveToApplicationSupport(
            data: manifestData,
            filename: "manifest.json",
            subdirectory: "journeys/\(manifest.journeyId)"
        )
    }

    private func markJourneyDownloaded(_ journeyId: String) {
        var downloadedJourneyIds = Set(
            Storage.loadFromUserDefaults(
                forKey: downloadedJourneysStorageKey,
                as: [String].self
            ) ?? []
        )
        downloadedJourneyIds.insert(journeyId)
        Storage.saveToUserDefaults(
            Array(downloadedJourneyIds).sorted(),
            forKey: downloadedJourneysStorageKey
        )
    }

    private func publishProgress(journeyId: String, completedCount: Int, totalCount: Int) {
        let safeTotalCount = max(totalCount, 1)
        let progress = Double(completedCount) / Double(safeTotalCount)
        downloadProgressContinuation?.yield(
            DownloadProgress(
                journeyId: journeyId,
                completedCount: completedCount,
                totalCount: safeTotalCount,
                progress: progress
            )
        )
    }

    private func loadPathMap(forKey key: String) -> [String: String] {
        Storage.loadFromUserDefaults(forKey: key, as: [String: String].self) ?? [:]
    }

    private func savePathMap(_ map: [String: String], forKey key: String) {
        Storage.saveToUserDefaults(map, forKey: key)
    }
}
