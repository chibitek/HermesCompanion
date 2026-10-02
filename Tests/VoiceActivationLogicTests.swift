import XCTest
import AVFoundation
@testable import HermesCompanion

final class VoiceActivationLogicTests: XCTestCase {
    @MainActor
    func testIdleVoiceControllersIgnoreSystemAudioInterruptionsAndCleanup() throws {
        let audio = AVAudioSession.sharedInstance()
        let category = audio.category
        let mode = audio.mode
        let options = audio.categoryOptions
        defer { try? audio.setCategory(category, mode: mode, options: options) }
        let phoneVoice = VoiceConversationManager()
        let carVoice = VoiceConversationManager()
        try audio.setCategory(.ambient, mode: .default)

        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
            object: audio, userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        XCTAssertEqual(audio.category, .ambient, "Idle observers must not reconfigure keyboard or other app audio")
        phoneVoice.stopConversation()
        carVoice.stopListening()
        carVoice.stopConversation()
        XCTAssertEqual(audio.category, .ambient, "Stopping an unused voice controller must leave audio alone")
    }

    @MainActor
    func testTextModeSurvivesAutomaticWakeListenerResumes() {
        let listener = WakePhraseListener()
        listener.suspendForTextInput()
        listener.start()
        listener.resume()
        listener.resumeFromBackground()
        listener.stop()
        XCTAssertTrue(listener.isSuspendedForTextInput)
        listener.allowAfterExplicitVoiceRequest()
        XCTAssertFalse(listener.isSuspendedForTextInput)
    }

    @MainActor
    func testTextBackgroundLifecyclePreservesAudioCategory() throws {
        let audio = AVAudioSession.sharedInstance()
        let originalCategory = audio.category
        let originalMode = audio.mode
        let originalOptions = audio.categoryOptions
        defer { try? audio.setCategory(originalCategory, mode: originalMode, options: originalOptions) }
        try audio.setCategory(.ambient, mode: .default)
        let client = HermesAPIClient(config: ConnectionConfig(
            baseURL: "https://hermes.invalid", apiKey: "", label: "Test"))
        let store = AppStore(client: client)
        store.beginBackgroundKeepAlive()
        XCTAssertEqual(audio.category, .ambient)
        store.endBackgroundTask()
        XCTAssertEqual(audio.category, .ambient)
        store.handleForegroundReturn()
        XCTAssertEqual(audio.category, .ambient)
    }

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
