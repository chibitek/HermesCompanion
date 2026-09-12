import XCTest
import SwiftUI
import AVFoundation
@testable import HermesCompanion

final class MarkdownBlocksTests: XCTestCase {
    @MainActor
    func testVoiceRemoteTurnOwnershipSurvivesLateCompletionAndRestart() {
        let manager = VoiceConversationManager()
        manager.isConversing = true
        let old = manager.beginRemoteTurn()
        let current = manager.beginRemoteTurn()
        XCTAssertFalse(manager.isCurrentRemoteTurn(old))
        XCTAssertTrue(manager.isCurrentRemoteTurn(current))
        XCTAssertTrue(manager.isThinking)
        manager.cancelThinking()
        XCTAssertFalse(manager.isCurrentRemoteTurn(current))
        XCTAssertFalse(manager.isThinking)
        manager.stopConversation()
        manager.isConversing = true
        XCTAssertFalse(manager.isCurrentRemoteTurn(current))
        let restarted = manager.beginRemoteTurn()
        XCTAssertTrue(manager.isCurrentRemoteTurn(restarted))
        manager.stopConversation()
        XCTAssertFalse(manager.isCurrentRemoteTurn(restarted))
    }

    @MainActor
    func testOldSpeechCallbacksCannotChangeReplacementPlayback() async {
        let manager = VoiceConversationManager()
        let old = AVSpeechUtterance(string: "First reply")
        let current = AVSpeechUtterance(string: "Current reply")
        manager.isConversing = true
        manager.registerSystemUtterance(old)
        manager.registerSystemUtterance(current)
        manager.systemSpeechDidStart(current)
        XCTAssertTrue(manager.isSpeaking)
        await manager.systemSpeechDidEnd(old, resumeListening: true)
        await manager.systemSpeechDidEnd(old, resumeListening: false)
        XCTAssertTrue(manager.isSpeaking)
        XCTAssertFalse(manager.isListening)
        manager.stopSpeaking()
        manager.systemSpeechDidStart(current)
        XCTAssertFalse(manager.isSpeaking)
        await manager.systemSpeechDidEnd(current, resumeListening: true)
        XCTAssertFalse(manager.isListening)
        manager.isConversing = false
    }

    @MainActor
    func testCurrentSpeechCancellationClearsSpeakingState() async {
        let manager = VoiceConversationManager()
        let utterance = AVSpeechUtterance(string: "Reply")
        manager.isConversing = true
        manager.registerSystemUtterance(utterance)
        manager.systemSpeechDidStart(utterance)
        XCTAssertTrue(manager.isSpeaking)
        await manager.systemSpeechDidEnd(utterance, resumeListening: false)
        XCTAssertFalse(manager.isSpeaking)
        XCTAssertFalse(manager.isListening)
        manager.systemSpeechDidStart(utterance)
        XCTAssertFalse(manager.isSpeaking)
        manager.isConversing = false
    }

    func testVoicePreservesServerAnswersAboutLatencyAndWarnings() {
        let response = "Latency is 300 milliseconds.\nResponse time includes tool execution.\nWarning: wait a second before retrying."
        XCTAssertEqual(VoiceConversationManager.normalizedRemoteResponse("\n " + response + " \n"), response)
        XCTAssertEqual(VoiceConversationManager.normalizedRemoteResponse(nil), "")
        XCTAssertEqual(VoiceConversationManager.normalizedRemoteResponse(" \n\t"), "")
    }

    @MainActor
    func testAppearanceSettingsFitNarrowAndWideContainers() {
        let appearance = AppearanceSettings()
        for width: CGFloat in [260, 420, 700] {
            let host = UIHostingController(rootView: AppearanceSettingsView(appearance: appearance)
                .environmentObject(appearance))
            let size = host.sizeThatFits(in: CGSize(width: width, height: 800))
            XCTAssertEqual(size.width, width, accuracy: 1)
            XCTAssertTrue(size.height.isFinite)
            XCTAssertGreaterThan(size.height, 0)
        }
        XCTAssertEqual(Set(ThemeRegistry.allThemes.map(\.id)).count, ThemeRegistry.allThemes.count)
    }

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
