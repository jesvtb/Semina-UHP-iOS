import XCTest
@testable import localKokoro

final class KokoroTextChunkerTests: XCTestCase {
    func testBreakParagraphsUsesDoubleNewlineFirst() {
        let text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
        let paragraphs = KokoroTextChunker.breakParagraphs(text: text)
        XCTAssertEqual(paragraphs, [
            "First paragraph.",
            "Second paragraph.",
            "Third paragraph.",
        ])
    }

    func testBreakParagraphsFallsBackToSingleNewline() {
        let text = "Line one.\nLine two."
        let paragraphs = KokoroTextChunker.breakParagraphs(text: text)
        XCTAssertEqual(paragraphs, ["Line one.", "Line two."])
    }

    func testBuildStreamingChunksPacksSentences() {
        let text = "Short one. Another short sentence. Final sentence here."
        let chunks = KokoroTextChunker.buildStreamingChunks(
            text: text,
            targetCharsPerChunk: 30
        )
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(chunks.allSatisfy { !$0.text.isEmpty })
    }
}
