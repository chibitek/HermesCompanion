import XCTest
@testable import HermesCompanion

final class ComposerSubmissionLogicTests: XCTestCase {
    func testStreamingWithTextQueuesInsteadOfStopping() {
        XCTAssertEqual(
            ComposerSubmissionLogic.action(isStreaming: true, canSend: true),
            .queue
        )
    }

    func testStreamingWithoutTextStillStops() {
        XCTAssertEqual(
            ComposerSubmissionLogic.action(isStreaming: true, canSend: false),
            .stop
        )
    }

    func testIdleWithTextSendsImmediately() {
        XCTAssertEqual(
            ComposerSubmissionLogic.action(isStreaming: false, canSend: true),
            .send
        )
    }

    func testIdleWithoutTextOpensVoice() {
        XCTAssertEqual(
            ComposerSubmissionLogic.action(isStreaming: false, canSend: false),
            .voice
        )
    }
}
