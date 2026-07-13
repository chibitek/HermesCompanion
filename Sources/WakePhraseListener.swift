import AVFoundation
import Foundation
import Speech
import UserNotifications

/// Low-profile foreground/background listener that opens hands-free voice mode
/// when the user says "Hey Hermes". iOS reserves true system-wide wake words for
/// Siri, so this listener operates while Hermes is active or in background
/// (using the `audio` background mode to keep the audio session alive).
@MainActor
final class WakePhraseListener: ObservableObject {
    var onWakePhrase: (() -> Void)?

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var hasInputTap = false
    private var isEnabled = false
    private var isPaused = false
    private var isBackground = false
    private var lastActivation = Date.distantPast
    private var recognitionGeneration = UUID()

    func start() {
        isEnabled = true
        isBackground = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.requestPermissionsIfNeeded()
            self.beginListeningIfPossible()
        }
    }

    func stop() {
        isEnabled = false
        isBackground = false
        tearDown()
    }

    func pause(deactivateAudioSession: Bool = true) {
        isPaused = true
        tearDown(deactivateAudioSession: deactivateAudioSession)
    }

    func resume() {
        isPaused = false
        isBackground = false
        beginListeningIfPossible()
    }

    /// Switch to background mode: keep listening with the audio session alive
    /// via the `audio` UIBackgroundMode. When the wake phrase is detected,
    /// post a local notification to bring the app to the foreground.
    func startBackgroundMode() {
        isBackground = true
        isPaused = false
        // Keep the audio session active so the audio engine keeps running
        // in the background. The `audio` background mode allows this.
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            FileLogger.shared.log("WakePhraseListener: background audio session failed: \(error.localizedDescription)")
        }
        beginListeningIfPossible()
    }

    /// Resume from background to foreground mode.
    func resumeFromBackground() {
        isBackground = false
        isPaused = false
        beginListeningIfPossible()
    }

    private func requestPermissionsIfNeeded() async {
        if AVAudioApplication.shared.recordPermission == .undetermined {
            await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { _ in continuation.resume() }
            }
        }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }
        }
    }

    private func beginListeningIfPossible() {
        guard isEnabled, !isPaused, !audioEngine.isRunning,
              AVAudioApplication.shared.recordPermission == .granted,
              SFSpeechRecognizer.authorizationStatus() == .authorized,
              let speechRecognizer, speechRecognizer.isAvailable,
              speechRecognizer.supportsOnDeviceRecognition
        else { return }

        tearDown(deactivateAudioSession: false)
        guard !hasInputTap else {
            FileLogger.shared.log("WakePhraseListener: input tap still active; skipping restart")
            return
        }
        let generation = UUID()
        recognitionGeneration = generation

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            FileLogger.shared.log("WakePhraseListener: audio session failed: \(error.localizedDescription)")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .confirmation
        recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.recognitionGeneration == generation else { return }
                if let text = result?.bestTranscription.formattedString,
                   WakePhraseParser.containsWakePhrase(text),
                   Date().timeIntervalSince(self.lastActivation) > 2 {
                    self.lastActivation = Date()
                    FileLogger.shared.log("WakePhraseListener: Hey Hermes detected (background: \(self.isBackground))")
                    self.pause(deactivateAudioSession: false)

                    if self.isBackground {
                        // Post a local notification to bring the app to foreground
                        let content = UNMutableNotificationContent()
                        content.title = "Hey Hermes"
                        content.body = "Voice activation detected — tap to open"
                        content.sound = .default
                        let request = UNNotificationRequest(
                            identifier: "hey-hermes-\(UUID().uuidString)",
                            content: content,
                            trigger: nil
                        )
                        UNUserNotificationCenter.current().add(request)
                    }

                    self.onWakePhrase?()
                    return
                }

                if error != nil || result?.isFinal == true {
                    self.tearDown()
                    guard self.isEnabled, !self.isPaused else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                        self?.beginListeningIfPossible()
                    }
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            tearDown()
            return
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        hasInputTap = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            FileLogger.shared.log("WakePhraseListener: microphone failed: \(error.localizedDescription)")
            isEnabled = false
            tearDown()
        }
    }

    private func tearDown(deactivateAudioSession: Bool = true) {
        recognitionGeneration = UUID()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if audioEngine.isRunning { audioEngine.stop() }
        if hasInputTap {
            // A tap remains installed even after iOS stops the engine while the
            // app transitions to the background. Remove it unconditionally.
            // Restarting the engine here can fail during that transition and
            // leave the old tap installed, causing installTap to abort when the
            // app becomes active again.
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        if deactivateAudioSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}