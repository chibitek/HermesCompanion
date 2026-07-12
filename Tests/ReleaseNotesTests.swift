import XCTest
@testable import HermesCompanion

final class ReleaseNotesTests: XCTestCase {
    func testPresentsWhenVersionChanges() {
        XCTAssertTrue(
            ReleaseNotes.shouldPresent(currentVersion: "1.8.29", lastPresentedVersion: "1.8.28")
        )
    }

    func testDoesNotPresentTwiceForSameVersion() {
        XCTAssertFalse(
            ReleaseNotes.shouldPresent(currentVersion: "1.8.29", lastPresentedVersion: "1.8.29")
        )
    }

    func testCurrentReleaseHasSpecificChanges() {
        let changes = ReleaseNotes.changes(for: "1.8.34")

        XCTAssertEqual(changes.count, 2)
        XCTAssertTrue(changes.contains { $0.localizedCaseInsensitiveContains("skills list") })
        XCTAssertTrue(changes.contains { $0.localizedCaseInsensitiveContains("collapsing") })
    }
}