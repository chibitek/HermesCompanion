import AVFoundation
import Foundation
import Speech
import UserNotifications

/// Low-profile foreground listener that opens hands-free voice mode when the
/// user says "Hey Hermes". iOS reserves true system-wide wake words for Siri,
/// so this opt-in listener operates only while Hermes is in the foreground.
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
    private(set) var isSuspendedForTextInput = false
    private var isBackground = false
    private var lastActivation = Date.distantPast
    private var recognitionGeneration = UUID()
    private var ownsAudioSession = false
    private let deactivateAudioSession: () -> Void

    init(deactivateAudioSession: @escaping () -> Void = {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }) {
        self.deactivateAudioSession = deactivateAudioSession
    }

    func start() {
        isEnabled = true
        isPaused = false
        isBackground = false
        guard !isSuspendedForTextInput else { return }
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

    /// Text entry is an explicit choice to leave the microphone alone. Ordinary
    /// sheet dismissal, app foregrounding, and dictation completion cannot undo it.
    func suspendForTextInput() {
        isSuspendedForTextInput = true
        pause()
    }

    func allowAfterExplicitVoiceRequest() {
        isSuspendedForTextInput = false
    }

    func pause(deactivateAudioSession: Bool = true) {
        isPaused = true
        tearDown(deactivateAudioSession: deactivateAudioSession)
        // Voice mode takes ownership without interrupting the shared session.
        if !deactivateAudioSession { ownsAudioSession = false }
    }

    func resume() {
        isPaused = false
        isBackground = false
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
        guard isEnabled, !isPaused, !isSuspendedForTextInput, !audioEngine.isRunning,
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
            ownsAudioSession = true
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
                    self.pause()

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
            // Transient failures happen on route changes (Bluetooth connect/drop).
            // Don't kill the listener permanently — tear down and retry like the
            // recognition-error path above.
            tearDown()
            guard isEnabled, !isPaused else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.beginListeningIfPossible()
            }
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
        if deactivateAudioSession, ownsAudioSession {
            self.deactivateAudioSession()
            ownsAudioSession = false
        }
    }
}
