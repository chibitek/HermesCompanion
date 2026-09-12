import XCTest
@testable import HermesCompanion

final class VoiceActivationLogicTests: XCTestCase {
    @MainActor
    func testCarPlayImplementsSystemDisconnectCallback() {
        let delegate = CarPlaySceneDelegate()
        XCTAssertTrue(delegate.responds(to: NSSelectorFromString("templateApplicationScene:didDisconnectInterfaceController:")))
        XCTAssertTrue(delegate.responds(to: NSSelectorFromString("templateApplicationScene:didConnectInterfaceController:")))
    }

    func testVoiceProviderSurfaceIsLocalOnly() {
        XCTAssertEqual(TTSProvider.visibleCases, [.apple])
    }

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
