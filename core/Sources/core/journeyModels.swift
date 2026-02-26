import Foundation

// MARK: - Download Manifest Models

public struct DownloadManifest: Codable, Sendable {
    public let journeyId: String
    public let version: Int
    public let stories: [DownloadManifestStory]

    public init(journeyId: String, version: Int, stories: [DownloadManifestStory]) {
        self.journeyId = journeyId
        self.version = version
        self.stories = stories
    }
}

public struct DownloadManifestStory: Codable, Identifiable, Sendable {
    public let storyId: String
    public let title: String
    public let audioUrl: String
    public let placeId: String
    public let sizeBytes: Int?
    public let materials: [StoryMaterial]

    public var id: String { storyId }

    public init(
        storyId: String,
        title: String,
        audioUrl: String,
        placeId: String,
        sizeBytes: Int? = nil,
        materials: [StoryMaterial] = []
    ) {
        self.storyId = storyId
        self.title = title
        self.audioUrl = audioUrl
        self.placeId = placeId
        self.sizeBytes = sizeBytes
        self.materials = materials
    }
}

// MARK: - Active Journey Models

public struct ActiveJourney: Codable, Identifiable, Sendable {
    public let id: UUID
    public let journeyId: String
    public let journeyVersion: Int
    public let sourceJourneyIds: [String]
    public let startedAt: Date
    public var status: JourneyStatus
    public var currentStopIndex: Int
    public var completedStopIndices: Set<Int>
    public var stories: [ActiveStory]
    public var liveActivityId: String?

    public init(
        id: UUID = UUID(),
        journeyId: String,
        journeyVersion: Int,
        sourceJourneyIds: [String],
        startedAt: Date,
        status: JourneyStatus,
        currentStopIndex: Int,
        completedStopIndices: Set<Int>,
        stories: [ActiveStory],
        liveActivityId: String? = nil
    ) {
        self.id = id
        self.journeyId = journeyId
        self.journeyVersion = journeyVersion
        self.sourceJourneyIds = sourceJourneyIds
        self.startedAt = startedAt
        self.status = status
        self.currentStopIndex = currentStopIndex
        self.completedStopIndices = completedStopIndices
        self.stories = stories
        self.liveActivityId = liveActivityId
    }
}

public enum JourneyStatus: String, Codable, Sendable {
    case notStarted
    case inProgress
    case paused
    case completed
}

public struct ActiveStory: Codable, Identifiable, Sendable {
    public let id: String
    public let placeIndex: Int
    public let title: String
    public let audioUrl: String
    public var localAudioPath: String?
    public var duration: TimeInterval?
    public var status: StoryStatus
    public var materials: [StoryMaterial]

    public init(
        id: String,
        placeIndex: Int,
        title: String,
        audioUrl: String,
        localAudioPath: String? = nil,
        duration: TimeInterval? = nil,
        status: StoryStatus,
        materials: [StoryMaterial]
    ) {
        self.id = id
        self.placeIndex = placeIndex
        self.title = title
        self.audioUrl = audioUrl
        self.localAudioPath = localAudioPath
        self.duration = duration
        self.status = status
        self.materials = materials
    }
}

public enum StoryStatus: String, Codable, Sendable {
    case notDownloaded
    case downloading
    case downloaded
    case playing
    case completed
}

public struct StoryMaterial: Codable, Identifiable, Sendable {
    public let id: String
    public let type: String
    public var localFilePath: String?
    public let payload: [String: JSONValue]

    public init(
        id: String,
        type: String,
        localFilePath: String? = nil,
        payload: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.type = type
        self.localFilePath = localFilePath
        self.payload = payload
    }

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        guard let idKey = DynamicCodingKey(stringValue: "id"),
              let typeKey = DynamicCodingKey(stringValue: "type") else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "StoryMaterial requires id and type keys."
                )
            )
        }

        self.id = try container.decode(String.self, forKey: idKey)
        self.type = try container.decode(String.self, forKey: typeKey)

        let localFilePathKeySnake = DynamicCodingKey(stringValue: "local_file_path")
        let localFilePathKeyCamel = DynamicCodingKey(stringValue: "localFilePath")
        if let localFilePathKeySnake {
            self.localFilePath = try container.decodeIfPresent(
                String.self,
                forKey: localFilePathKeySnake
            )
        } else {
            self.localFilePath = nil
        }
        if self.localFilePath == nil, let localFilePathKeyCamel {
            self.localFilePath = try container.decodeIfPresent(
                String.self,
                forKey: localFilePathKeyCamel
            )
        }

        var payload: [String: JSONValue] = [:]
        for key in container.allKeys {
            if key.stringValue == "id"
                || key.stringValue == "type"
                || key.stringValue == "local_file_path"
                || key.stringValue == "localFilePath" {
                continue
            }
            if let value = try container.decodeIfPresent(
                JSONValue.self,
                forKey: key
            ) {
                payload[key.stringValue] = value
            }
        }
        self.payload = payload
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(id, forKey: DynamicCodingKey(stringValue: "id")!)
        try container.encode(type, forKey: DynamicCodingKey(stringValue: "type")!)
        if let localFilePath {
            try container.encode(
                localFilePath,
                forKey: DynamicCodingKey(stringValue: "local_file_path")!
            )
        }
        for (payloadKey, payloadValue) in payload {
            guard let codingKey = DynamicCodingKey(stringValue: payloadKey) else {
                continue
            }
            try container.encode(payloadValue, forKey: codingKey)
        }
    }
}
