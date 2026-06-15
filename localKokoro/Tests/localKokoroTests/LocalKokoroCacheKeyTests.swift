import XCTest
@testable import localKokoro

final class LocalKokoroCacheKeyTests: XCTestCase {
    func testArtifactFileNameIsStableForSameInputs() {
        let config = KokoroSynthesisConfig()
        let first = LocalKokoroCacheKey.artifactFileName(
            journeyId: "journey-1",
            manifestVersion: 3,
            storyId: "story-1",
            config: config,
            script: "Hello world."
        )
        let second = LocalKokoroCacheKey.artifactFileName(
            journeyId: "journey-1",
            manifestVersion: 3,
            storyId: "story-1",
            config: config,
            script: "Hello world."
        )
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasSuffix(".m4a"))
    }

    func testArtifactFileNameChangesWhenManifestVersionChanges() {
        let config = KokoroSynthesisConfig()
        let versionOne = LocalKokoroCacheKey.artifactFileName(
            journeyId: "journey-1",
            manifestVersion: 1,
            storyId: "story-1",
            config: config,
            script: "Hello world."
        )
        let versionTwo = LocalKokoroCacheKey.artifactFileName(
            journeyId: "journey-1",
            manifestVersion: 2,
            storyId: "story-1",
            config: config,
            script: "Hello world."
        )
        XCTAssertNotEqual(versionOne, versionTwo)
    }
}
