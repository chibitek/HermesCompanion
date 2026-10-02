import XCTest
@testable import HermesCompanion

final class ComposerSubmissionLogicTests: XCTestCase {
    func testStreamingWithTextQueuesInsteadOfStopping() {
        XCTAssertEqual(
            ComposerSubmissionLogic.action(isStreaming: true, canSend: true),
            .queue
        )
    }

    func testStreamingWithoutTextComposesWithoutStopping() {
        XCTAssertEqual(
            ComposerSubmissionLogic.action(isStreaming: true, canSend: false),
            .compose
        )
    }

    func testIdleWithTextSendsImmediately() {
        XCTAssertEqual(
            ComposerSubmissionLogic.action(isStreaming: false, canSend: true),
            .send
        )
    }

    func testIdleWithoutTextComposesMessage() {
        XCTAssertEqual(
            ComposerSubmissionLogic.action(isStreaming: false, canSend: false),
            .compose
        )
    }
}
