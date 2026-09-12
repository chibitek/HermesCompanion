import XCTest
@testable import HermesCompanion

final class VoiceActivationLogicTests: XCTestCase {
    func testWakeListeningRequiresFreshOptIn() {
        let name = "wake-consent-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set(true, forKey: "hey_hermes_enabled")
        SharedDefaults.migrateWakeListeningConsent(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: "hey_hermes_enabled"))

        defaults.set(true, forKey: "hey_hermes_enabled")
        SharedDefaults.migrateWakeListeningConsent(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: "hey_hermes_enabled"))
    }

    func testNewInstallDoesNotEnableWakeListening() {
        let name = "wake-consent-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        SharedDefaults.migrateWakeListeningConsent(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: "hey_hermes_enabled"))
    }

    @MainActor
    func testIdleWakeListenerDoesNotReleaseAnotherAudioSession() {
        var releases = 0
        let listener = WakePhraseListener(deactivateAudioSession: { releases += 1 })
        listener.resumeFromBackground()
        listener.pause()
        listener.resume()
        listener.stop()
        XCTAssertEqual(releases, 0)
    }

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
