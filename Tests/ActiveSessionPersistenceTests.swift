import XCTest
@testable import HermesCompanion

final class ActiveSessionPersistenceTests: XCTestCase {
    func testRestoresSavedSessionOnlyForMatchingConnection() {
        let defaults = isolatedDefaults()
        let persistence = ActiveSessionPersistence(defaults: defaults)

        persistence.save(sessionID: "session-42", for: "http://hermes-one:8642/")

        XCTAssertEqual(persistence.load(for: "http://hermes-one:8642"), "session-42")
        XCTAssertNil(persistence.load(for: "http://hermes-two:8642"))
    }

    func testClearRemovesSavedSessionForConnection() {
        let defaults = isolatedDefaults()
        let persistence = ActiveSessionPersistence(defaults: defaults)
        persistence.save(sessionID: "session-42", for: "http://hermes-one:8642")

        persistence.clear(for: "http://hermes-one:8642/")

        XCTAssertNil(persistence.load(for: "http://hermes-one:8642"))
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "ActiveSessionPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
