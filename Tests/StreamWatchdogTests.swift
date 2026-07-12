import XCTest
@testable import HermesCompanion

final class StreamWatchdogTests: XCTestCase {
    func testActivityResetsTimeout() async throws {
        let watchdog = StreamWatchdogManager()
        let fired = expectation(description: "timeout fires only after latest activity")
        fired.expectedFulfillmentCount = 1

        watchdog.arm(after: 0.08) { fired.fulfill() }
        try await Task.sleep(for: .milliseconds(50))
        watchdog.recordActivity()

        await fulfillment(of: [fired], timeout: 0.10)
    }

    func testCancelPreventsTimeout() async throws {
        let watchdog = StreamWatchdogManager()
        let fired = expectation(description: "cancelled timeout")
        fired.isInverted = true

        watchdog.arm(after: 0.05) { fired.fulfill() }
        watchdog.cancel()

        await fulfillment(of: [fired], timeout: 0.10)
    }
}
