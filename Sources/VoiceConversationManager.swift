import Foundation
import SwiftUI
import AVFoundation
import Speech

/// Voice conversation mode: local (on-device) or remote (Hermes API).
enum ConversationMode: String, CaseIterable {
    case local = "Local"
    case remote = "Remote"

    var icon: String {
        switch self {
        case .local: return "iphone.radiowaves.left.and.right"
        case .remote: return "cloud.fill"
        }
    }

    var toggled: ConversationMode {
        switch self {
        case .local: return .remote
        case .remote: return .local
        }
    }
}

/// Voice conversation mode for live 2-way voice interaction.
///
/// In **local** mode:
/// 1. Records audio and transcribes via SFSpeechRecognizer
/// 2. Generates response on-device via LocalLLMManager (Apple Foundation Models)
/// 3. Speaks the response using AVSpeechSynthesizer
/// 4. Resumes listening — fully hands-free
///
/// In **remote** mode:
/// 1. Records audio and transcribes via SFSpeechRecognizer
/// 2. Sends transcribed text to Hermes API
/// 3. Speaks the response using AVSpeechSynthesizer
/// 4. Resumes listening — fully hands-free
@MainActor
final class VoiceConversationManager: ObservableObject {
    @Published var isConversing = false
    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var isThinking = false
    @Published var transcribedText = ""
    @Published var spokenResponse = ""
    @Published var hasPermission = false
    @Published var conversationMode: ConversationMode = .local
    @Published var audioLevel: Float = 0.0

    // Voice settings (persisted via @AppStorage in VoiceConversationPage)
    var voiceSpeed: Float = 0.5
    var voicePitch: Float = 1.0
    var voiceIdentifier: String = ""

    // Local LLM
    let localLLM = LocalLLMManager()

    // Speech recognition
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // Audio level monitoring
    private var levelTimer: Timer?
    private var audioMetersNode: AVAudioInputNode? { audioEngine.inputNode }

    // TTS
    private let synthesizer = AVSpeechSynthesizer()
    private let delegateBridge = SpeechDelegateBridge()

    // Conversation flow
    private var onTranscriptionComplete: ((String) -> Void)?
    private var onLocalResponse: ((String) -> Void)?

    // Barge-in: mic level monitoring during TTS playback
    private var bargeInCheckTimer: Timer?
    private var bargeInTriggerCount = 0
    private let bargeInThreshold: Float = 0.15

    // Silence detection: auto-finalize when user stops talking
    private var silenceTimer: Timer?
    private var silenceTimeout: TimeInterval = 1.5  // seconds of silence before finalizing
    private var lastTranscriptionTime: Date = .distantPast
    private var lastTranscribedText: String = ""

    // Debounce for finalization
    private var isFinalizing = false

    init() {
        delegateBridge.manager = self
        synthesizer.delegate = delegateBridge

        // Load voice settings from UserDefaults (set via Settings > Voice)
        voiceSpeed = UserDefaults.standard.float(forKey: "voice_speed")
        if voiceSpeed == 0 { voiceSpeed = 0.5 }
        voicePitch = UserDefaults.standard.float(forKey: "voice_pitch")
        if voicePitch == 0 { voicePitch = 1.0 }
        voiceIdentifier = UserDefaults.standard.string(forKey: "voice_identifier") ?? ""

        // Default to local mode only if the on-device LLM is available AND
        // there's no Hermes server connection. When connected, always prefer
        // remote (Hermes) so the voice conversation has the same session
        // context and memory as the typed chat.
        if localLLM.isAvailable && !isHermesConnected {
            conversationMode = .local
        } else {
            conversationMode = .remote
        }

        // Observe audio session interruptions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    /// Whether a Hermes server is connected. Set by ChatView / AppStore.
    /// When true, voice mode should default to remote so the conversation
    /// shares context with the typed chat.
    var isHermesConnected: Bool = true

    /// Re-evaluate the default mode based on current connection state.
    /// Call when the Hermes connection state changes.
    func refreshDefaultMode() {
        if localLLM.isAvailable && !isHermesConnected {
            conversationMode = .local
        } else {
            conversationMode = .remote
        }
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            stopListening()
            stopSpeaking()
        case .ended:
            // Don't auto-resume; let the user tap to continue
            break
        @unknown default:
            break
        }
    }

    // MARK: - Permission

    func requestAuthorization() async {
        // Microphone
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            AVAudioApplication.requestRecordPermission { _ in
                continuation.resume()
            }
        }

        // Speech recognition
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in
                continuation.resume()
            }
        }

        let micGranted = AVAudioApplication.shared.recordPermission == .granted
        let speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        hasPermission = micGranted && speechGranted
    }

    // MARK: - Start/Stop Conversation

    /// Start a live conversation. In local mode, responses are generated on-device.
    /// In remote mode, `onTranscription` is called and the caller sends to Hermes API.
    func startConversation(
        onTranscription: ((String) -> Void)? = nil,
        onLocalResponse: ((String) -> Void)? = nil
    ) {
        guard hasPermission else {
            Task {
                await requestAuthorization()
                if hasPermission {
                    startConversation(
                        onTranscription: onTranscription,
                        onLocalResponse: onLocalResponse
                    )
                }
            }
            return
        }

        isConversing = true
        self.onTranscriptionComplete = onTranscription
        self.onLocalResponse = onLocalResponse
        startListening()
    }

    func stopConversation() {
        isConversing = false
        stopListening()
        stopSpeaking()
        stopBargeInMonitoring()
        isThinking = false
        isFinalizing = false
        onTranscriptionComplete = nil
        onLocalResponse = nil
    }

    /// Finish a remote Hermes turn after the caller has sent the transcription
    /// and reconciled the session messages.
    func completeRemoteTurn(response: String?) {
        isThinking = false
        let cleanResponse = response?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if cleanResponse.isEmpty {
            isFinalizing = false
            return
        }
        speakResponse(cleanResponse)
    }

    // MARK: - Listening

    func startListening() {
        guard isConversing else { return }
        // If currently speaking, stop TTS first (barge-in by button tap)
        if isSpeaking {
            stopSpeaking()
        }
        guard !isThinking else { return }
        guard !isListening else { return }  // Prevent double-start
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        // CRITICAL: Stop the engine and remove any existing tap BEFORE setting
        // up a new tap. AVAudioEngine throws an Objective-C exception
        // ("Tap is already installed on bus") if you call installTap on a
        // node that already has one, and that exception is uncatchable in
        // Swift and crashes the app. We must stop the engine first.
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        cancelRecognition()

        transcribedText = ""
        isListening = true

        // Configure audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            isListening = false
            return
        }

        // Set up recognition
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            isListening = false
            return
        }
        recognitionRequest.shouldReportPartialResults = true
        if #available(iOS 16, *) {
            recognitionRequest.addsPunctuation = true
        }

        // Recognition task with final result detection
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if error != nil {
                // Don't auto-restart on error -- this was causing infinite loops
                // and crashes. Just stop listening and let the user tap to resume.
                self.stopListening()
                return
            }

            if let result = result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor [weak self] in
                    self?.transcribedText = text
                    self?.resetSilenceTimer()
                }

                if result.isFinal {
                    self.finalizeTranscription(text)
                }
            }
        }

        // Audio engine for live mic input. Note: the tap was already removed
        // at the top of this function to avoid the "tap already installed"
        // crash, so we just install the new one here.
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, let recognitionRequest = self.recognitionRequest else { return }
            recognitionRequest.append(buffer)

            // Calculate RMS audio level for visualizer.
            if buffer.frameLength > 0 {
                Task { @MainActor [weak self] in
                    self?.updateAudioLevel(from: buffer)
                }
            }
        }

        do {
            if !audioEngine.isRunning {
                audioEngine.prepare()
                try audioEngine.start()
            }
            startLevelMonitoring()
        } catch {
            stopListening()
        }
    }

    /// Calculate RMS audio level from an audio buffer for the visualizer.
    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        // Normalize to 0...1 range (typical mic RMS is 0...0.5)
        let level = min(1.0, rms * 3.0)
        audioLevel = level
    }

    /// Start a timer-based fallback for audio level polling.
    private func startLevelMonitoring() {
        stopLevelMonitoring()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // If audio engine is running, the tap handler updates audioLevel.
                // This timer ensures the level decays when no audio is coming in.
                if !self.isListening {
                    self.audioLevel *= 0.7
                }
            }
        }
    }

    private func stopLevelMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioLevel = 0
    }

    func stopListening() {
        isListening = false
        stopLevelMonitoring()
        stopSilenceTimer()
        isFinalizing = false

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Finalize the current transcription and trigger the conversation flow.
    /// In local mode: generates a response via LocalLLMManager, speaks it, resumes listening.
    /// In remote mode: calls the onTranscriptionComplete callback.
    func finalizeTranscription(_ text: String) {
        let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty, !isFinalizing else {
            // Empty transcription -- just stop listening.
            // Don't auto-restart to avoid loops. User can tap mic to resume.
            stopListening()
            return
        }

        isFinalizing = true
        stopListening()

        switch conversationMode {
        case .local:
            isThinking = true
            Task {
                let response = await localLLM.generateResponse(to: finalText)
                isThinking = false
                isFinalizing = false
                if isConversing {
                    speakResponse(response)
                    onLocalResponse?(response)
                }
            }

        case .remote:
            onTranscriptionComplete?(finalText)
            // For remote mode, isFinalizing will be reset when speakResponse is called
            // by the caller after receiving the API response.
        }
    }

    // MARK: - Silence Detection

    /// Reset the silence timer. Called whenever new transcription text arrives.
    /// If no new text arrives for `silenceTimeout` seconds, the transcription is finalized.
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isListening, !self.isFinalizing else { return }
                let text = self.transcribedText
                if !text.isEmpty {
                    self.finalizeTranscription(text)
                }
            }
        }
    }

    private func stopSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    // MARK: - Barge-In (mic level monitoring during TTS)

    /// During TTS, we monitor the existing audioLevel published property
    /// instead of creating a second AVAudioEngine (which causes deadlocks).
    /// The level timer in startLevelMonitoring() already runs during playback
    /// since we use playAndRecord category.

    private func startBargeInMonitoring() {
        stopBargeInMonitoring()
        bargeInCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isSpeaking else { return }
                if self.audioLevel > self.bargeInThreshold {
                    self.bargeInTriggerCount += 1
                    if self.bargeInTriggerCount >= 3 {
                        self.handleBargeIn()
                    }
                } else {
                    self.bargeInTriggerCount = 0
                }
            }
        }
    }

    private func stopBargeInMonitoring() {
        bargeInCheckTimer?.invalidate()
        bargeInCheckTimer = nil
        bargeInTriggerCount = 0
    }

    /// User started speaking while AI was talking -- stop TTS immediately
    /// and switch to listening mode.
    private func handleBargeIn() {
        stopBargeInMonitoring()
        stopSpeaking()
        // Small delay to let audio session switch from playback to recording
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2s
            self?.startListening()
        }
    }

    // MARK: - TTS

    /// Speak a text response using AVSpeechSynthesizer.
    /// Automatically resumes listening after speech completes.
    func speakResponse(_ text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty, isConversing else { return }

        // Sync voice settings from UserDefaults
        voiceSpeed = UserDefaults.standard.float(forKey: "voice_speed")
        voicePitch = UserDefaults.standard.float(forKey: "voice_pitch")
        voiceIdentifier = UserDefaults.standard.string(forKey: "voice_identifier") ?? ""
        if voiceSpeed == 0 { voiceSpeed = 0.5 }
        if voicePitch == 0 { voicePitch = 1.0 }

        isFinalizing = false
        spokenResponse = cleanText
        isSpeaking = true

        // Configure audio session for playback + recording (for barge-in)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            // Continue anyway -- TTS may still work
        }

        let utterance = AVSpeechUtterance(string: cleanText)
        // Use selected voice identifier if available, otherwise system default
        if !voiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        }
        // Map slider (0.1...1.0) to AVSpeechUtterance rate range (0...1, default 0.5)
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate,
                            min(AVSpeechUtteranceMaximumSpeechRate, voiceSpeed))
        utterance.pitchMultiplier = voicePitch
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.3

        synthesizer.speak(utterance)

        // Start monitoring mic for barge-in (user interrupting the AI)
        startBargeInMonitoring()
    }

    func stopSpeaking() {
        stopBargeInMonitoring()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    // MARK: - Mode Toggle

    func toggleMode() {
        conversationMode = conversationMode.toggled
        if conversationMode == .local && !localLLM.isAvailable {
            localLLM.refreshAvailability()
            if !localLLM.isAvailable {
                // Fallback to remote
                conversationMode = .remote
            }
        }
    }

    // MARK: - Voice Settings Sync

    /// Reload voice settings from UserDefaults. Call this when the voice page
    /// appears, in case the user changed settings in Settings > Voice.
    func syncVoiceSettings() {
        voiceSpeed = UserDefaults.standard.float(forKey: "voice_speed")
        if voiceSpeed == 0 { voiceSpeed = 0.5 }
        voicePitch = UserDefaults.standard.float(forKey: "voice_pitch")
        if voicePitch == 0 { voicePitch = 1.0 }
        voiceIdentifier = UserDefaults.standard.string(forKey: "voice_identifier") ?? ""
    }

    /// Sync voice settings from @AppStorage values stored in the voice page.
    func updateVoiceSettings(speed: Float, pitch: Float, identifier: String) {
        voiceSpeed = speed
        voicePitch = pitch
        voiceIdentifier = identifier
    }

    // MARK: - Private

    func cancelRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
}

// MARK: - Speech Delegate Bridge

/// Bridge object that receives AVSpeechSynthesizerDelegate callbacks
/// and forwards them to the VoiceConversationManager on the main actor.
private final class SpeechDelegateBridge: NSObject, AVSpeechSynthesizerDelegate {
    weak var manager: VoiceConversationManager?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            manager?.isSpeaking = true
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard let manager = manager else { return }
            manager.isSpeaking = false
            // Resume listening after the response is spoken.
            // Add a small delay to let the audio session settle.
            if manager.isConversing {
                try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3s
                manager.startListening()
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            manager?.isSpeaking = false
        }
    }
}
