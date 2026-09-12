import XCTest
import SwiftUI
@testable import HermesCompanion

final class MarkdownBlocksTests: XCTestCase {
    @MainActor
    func testMessageBubblesFitTheirContainerAndReflowLongText() {
        let appearance = AppearanceSettings()
        let content = String(repeating: "A message that must wrap within its available window. ", count: 30)
        for isUser in [true, false] {
            let host = UIHostingController(rootView: GlassBubble(content: content, isUser: isUser, fixedFontSize: 14)
                .environmentObject(appearance))
            let narrow = host.sizeThatFits(in: CGSize(width: 240, height: 10000))
            let wide = host.sizeThatFits(in: CGSize(width: 700, height: 10000))
            XCTAssertTrue(narrow.height.isFinite)
            XCTAssertTrue(wide.height.isFinite)
            XCTAssertGreaterThan(narrow.height, wide.height)
            XCTAssertEqual(narrow.width, 240, accuracy: 1)
            XCTAssertEqual(wide.width, 700, accuracy: 1)
        }
    }

    func testParagraphOnly() {
        let blocks = MarkdownBlocks.parse("Hello **world**.")
        XCTAssertEqual(blocks, [.text("Hello **world**.")])
    }

    func testHeadingStripped() {
        let blocks = MarkdownBlocks.parse("## Title here")
        XCTAssertEqual(blocks, [.text("Title here")])
    }

    func testUnorderedList() {
        let blocks = MarkdownBlocks.parse("- alpha\n- beta")
        XCTAssertEqual(blocks, [.list(["alpha", "beta"], ordered: false)])
    }

    func testOrderedList() {
        let blocks = MarkdownBlocks.parse("1. one\n2. two")
        XCTAssertEqual(blocks, [.list(["one", "two"], ordered: true)])
    }

    func testTimestampNotAList() {
        let blocks = MarkdownBlocks.parse("12:30 stays text")
        XCTAssertEqual(blocks, [.text("12:30 stays text")])
    }

    func testFencedCodeBlock() {
        let md = "```swift\nlet x = 1\n```"
        let blocks = MarkdownBlocks.parse(md)
        XCTAssertEqual(blocks, [.code(language: "swift", code: "let x = 1")])
    }

    func testUnclosedFenceRendersWhatWeHave() {
        // Mid-stream: fence opened but never closed — must not vanish.
        let blocks = MarkdownBlocks.parse("```py\nprint(1)")
        XCTAssertEqual(blocks, [.code(language: "py", code: "print(1)")])
    }

    func testMixedDocument() {
        let md = """
        # Title

        Hello **world**.

        - alpha
        - beta

        ```swift
        let x = 1 // ```
        ```

        1. one
        2. two
        """
        let blocks = MarkdownBlocks.parse(md)
        XCTAssertEqual(blocks.count, 5)
        XCTAssertEqual(blocks[0], .text("Title"))
        XCTAssertEqual(blocks[1], .text("Hello **world**."))
        XCTAssertEqual(blocks[2], .list(["alpha", "beta"], ordered: false))
        XCTAssertEqual(blocks[3], .code(language: "swift", code: "let x = 1 // ```"))
        XCTAssertEqual(blocks[4], .list(["one", "two"], ordered: true))
    }

    func testEmptyInput() {
        XCTAssertEqual(MarkdownBlocks.parse(""), [])
        XCTAssertEqual(MarkdownBlocks.parse("   \n  "), [])
    }
}
