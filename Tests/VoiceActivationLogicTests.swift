import XCTest
@testable import HermesCompanion

final class VoiceActivationLogicTests: XCTestCase {
    func testEndpointingAllowsNaturalPauses() {
        XCTAssertGreaterThanOrEqual(VoiceEndpointingPolicy.silenceTimeout, 1.5)
    }

    func testWakePhraseMatchesCaseAndPunctuation() {
        XCTAssertTrue(WakePhraseParser.containsWakePhrase("Hey Hermes"))
        XCTAssertTrue(WakePhraseParser.containsWakePhrase("hey, hermes!"))
        XCTAssertTrue(WakePhraseParser.containsWakePhrase("Okay hey Hermes can you help me"))
    }

    func testWakePhraseRejectsNearMatches() {
        XCTAssertFalse(WakePhraseParser.containsWakePhrase("Hermes is useful"))
        XCTAssertFalse(WakePhraseParser.containsWakePhrase("Hey Herman"))
    }
}
