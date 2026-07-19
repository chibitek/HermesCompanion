import Foundation
import SwiftUI
import AVFoundation
import Speech
import Network

/// Voice conversation manager for live 2-way voice interaction with Hermes.
///
/// Flow:
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
    @Published var audioLevel: Float = 0.0
    @Published var voiceError: String?

    // Voice settings (persisted via @AppStorage in VoiceSettingsView)
    var voiceSpeed: Float = 0.5
    var voicePitch: Float = 1.0
    var voiceIdentifier: String = ""

    // Speech recognition
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var hasInstalledInputTap = false
    private var isStoppingListening = false

    // Audio level monitoring
    private var levelTimer: Timer?

    // TTS
    private let synthesizer = AVSpeechSynthesizer()
    private let delegateBridge = SpeechDelegateBridge()

    // Conversation flow
    private var onTranscriptionComplete: ((String) -> Void)?
    // Called before starting voice mode to stop background audio
    var onStopBackgroundAudio: (() -> Void)?

    // Barge-in: mic level monitoring during TTS playback
    private var bargeInCheckTimer: Timer?
    private var bargeInTriggerCount = 0
    private let bargeInThreshold: Float = 0.15

    // Silence detection: auto-finalize when user stops talking
    private var silenceTimer: Timer?
    private let silenceTimeout = VoiceEndpointingPolicy.silenceTimeout
    // Debounce for finalization
    private var isFinalizing = false
    private var pendingConversationStartID: UUID?

    // Safety net: if thinking lasts too long, cancel and resume listening.
    // 20s — long enough for tool calls, short enough to not feel dead.
    private var thinkingSafetyTimer: Timer?
    private let thinkingSafetyTimeout: TimeInterval = 20

    init() {
        delegateBridge.manager = self
        synthesizer.delegate = delegateBridge

        // Load voice settings from UserDefaults (set via Settings > Voice)
        syncVoiceSettings()

        // Observe audio session interruptions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // If we're in a voice conversation, don't fully stop — just pause.
            // The audio background mode keeps the session alive.
            if isConversing {
                stopListening()
            } else {
                stopListening()
                stopSpeaking()
            }
        case .ended:
            // Auto-resume if still in conversation mode
            if isConversing {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s for session to settle
                    self.startListening()
                }
            }
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

    /// Start a live conversation. `onTranscription` is called when the user's
    /// speech is finalized; the caller sends it to the Hermes API.
    func startConversation(
        onTranscription: ((String) -> Void)? = nil
    ) {
        guard hasPermission else {
            let startID = UUID()
            pendingConversationStartID = startID
            Task {
                await requestAuthorization()
                guard pendingConversationStartID == startID else { return }
                if hasPermission {
                    startConversation(
                        onTranscription: onTranscription
                    )
                } else {
                    pendingConversationStartID = nil
                    voiceError = "Microphone and speech recognition permissions are required."
                }
            }
            return
        }

        pendingConversationStartID = nil
        isConversing = true
        voiceError = nil
        self.onTranscriptionComplete = onTranscription
        startListening()
    }

    func stopConversation() {
        pendingConversationStartID = nil
        isConversing = false
        stopListening()
        stopSpeaking()
        stopBargeInMonitoring()
        isThinking = false
        isFinalizing = false
        voiceError = nil
        onTranscriptionComplete = nil
        // Deactivate audio session now that conversation is fully over
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Start speaking the first sentence of a response while the rest is still
    /// streaming from the server. This cuts perceived latency — the user hears
    /// the response start while the model is still generating.
    func startEarlySpeaking(text: String) {
        FileLogger.shared.log("VoiceManager: startEarlySpeaking with: \(text.prefix(80))")
        isThinking = false
        isFinalizing = false
        invalidateThinkingSafetyTimer()
        voiceError = nil
        // Stop any active listening/recording before TTS to prevent
        // audio engine conflicts that crash the app.
        if isListening {
            stopListening(resetFinalizing: true)
        }
        // Ensure audio engine is fully stopped
        if audioEngine.isRunning {
            audioEngine.stop()
            removeInputTapIfNeeded()
        }
        spokenResponse = text
        speakResponse(text)
    }

    func completeRemoteTurn(response: String?) {
        FileLogger.shared.log("completeRemoteTurn called with response: \(String(describing: response?.prefix(120)))")
        isThinking = false
        isFinalizing = false
        invalidateThinkingSafetyTimer()
        
        // If we already started speaking via startEarlySpeaking, just update
        // the displayed text with the full response. Don't restart TTS.
        if isSpeaking {
            FileLogger.shared.log("completeRemoteTurn: already speaking from early TTS, updating text only")
            let rawResponse = response?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cleanResponse = filterGatewayArtifacts(rawResponse)
            if !cleanResponse.isEmpty {
                spokenResponse = cleanResponse
            }
            return
        }
        
        let rawResponse = response?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanResponse = filterGatewayArtifacts(rawResponse)
        
        if cleanResponse.isEmpty {
            FileLogger.shared.log("VoiceManager: response is empty after filtering, failing turn")
            failRemoteTurn(message: "Hermes did not return a voice response.")
            return
        }
        voiceError = nil
        // Guard against double-stop crash: only stop listening if currently active.
        // startEarlySpeaking may have already torn down the audio engine.
        if isListening {
            stopListening()
        }
        speakResponse(cleanResponse)
    }
    
    /// Remove gateway-injected latency warnings, status messages, and other
    /// non-conversational text that shouldn't be spoken aloud.
    private func filterGatewayArtifacts(_ text: String) -> String {
        var cleaned = text
        // Remove lines containing latency warnings (e.g. "Hermes 9000+ milliseconds")
        cleaned = cleaned.components(separatedBy: "\n").filter { line in
            let lower = line.lowercased()
            let isLatencyWarning = lower.contains("millisecond") || lower.contains("latency") || lower.contains("response time")
            let isGatewayStatus = lower.contains("warning:") && (lower.contains("ms") || lower.contains("second"))
            return !isLatencyWarning && !isGatewayStatus
        }.joined(separator: "\n")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Finish a remote Hermes turn when the network request fails or returns no
    /// speakable assistant message. Keep the conversation hands-free by
    /// returning to listening after the error is surfaced.
    func failRemoteTurn(message: String) {
        FileLogger.shared.log("failRemoteTurn called: \(message)")
        isThinking = false
        isFinalizing = false
        invalidateThinkingSafetyTimer()
        voiceError = message

        // Only speak the error if the voice conversation is still active.
        // If the user closed the voice page, don't speak into an empty room.
        guard isConversing else { return }
        speakResponse(message)

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self,
                  self.isConversing,
                  !self.isListening,
                  !self.isSpeaking,
                  !self.isThinking
            else { return }
            self.startListening()
        }
    }

    /// Forcefully cancel the current thinking / network wait and return to
    /// listening. Called by the UI when the user taps "Stop" while waiting for
    /// a remote response.
    func cancelThinking() {
        guard isConversing else { return }
        invalidateThinkingSafetyTimer()
        isThinking = false
        isFinalizing = false
        voiceError = nil
        stopListening()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)  // 0.15s (was 0.3s)
            guard let self,
                  self.isConversing,
                  !self.isListening,
                  !self.isSpeaking,
                  !self.isThinking
            else { return }
            self.startListening()
        }
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
        // Re-entry guard: if the audio engine is already running with a tap
        // installed, don't try to start again. This prevents the crash that
        // happens when startListening is called from multiple async paths
        // (e.g. TTS didFinish + barge-in) before the first call completes.
        if audioEngine.isRunning && hasInstalledInputTap {
            return
        }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            voiceError = "Speech recognition is unavailable."
            return
        }
        isStoppingListening = false
        voiceError = nil

        // Stop the background silent audio player before starting voice mode.
        // The silent player uses .playback category; switching to .playAndRecord
        // while it's running can crash the audio engine.
        onStopBackgroundAudio?()

        // CRITICAL: Stop the engine and remove any existing tap BEFORE setting
        // up a new tap. AVAudioEngine throws an Objective-C exception
        // ("Tap is already installed on bus") if you call installTap on a
        // node that already has one, and that exception is uncatchable in
        // Swift and crashes the app. We must stop the engine first.
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        removeInputTapIfNeeded()

        cancelRecognition()

        transcribedText = ""
        isListening = true

        // Configure audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try? audioSession.setPreferredSampleRate(44_100)
            try? audioSession.setPreferredInputNumberOfChannels(1)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            isListening = false
            voiceError = "Microphone unavailable."
            return
        }

        // Set up recognition
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            isListening = false
            return
        }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true
        // Force server-based recognition to free up the CPU for the Matrix rain
        // animation. On-device recognition runs a neural net on the CPU/GPU
        // which competes with the Canvas rendering and causes UI freezes.
        // Server recognition sends audio to Apple's servers, leaving the
        // device CPU free for the visualizer.
        recognitionRequest.requiresOnDeviceRecognition = false

        // Recognition task with final result detection
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                // Guard against callbacks after stopListening — the recognition
                // request may be nil if we already cancelled. This prevents the
                // crash that happens when the callback fires during the
                // listen->think transition.
                guard self.recognitionRequest != nil || self.isListening else {
                    if self.isStoppingListening {
                        self.isStoppingListening = false
                    }
                    return
                }

                if let error {
                    if self.isStoppingListening || self.isBenignRecognitionCancellation(error) {
                        self.isStoppingListening = false
                        if !self.isFinalizing {
                            self.stopListening()
                        }
                        return
                    }

                    // Don't auto-restart on error -- this was causing infinite loops
                    // and crashes. Just stop listening and let the user tap to resume.
                    self.stopListening()
                    self.voiceError = error.localizedDescription
                    return
                }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.transcribedText = text
                    self.resetSilenceTimer()

                    if result.isFinal {
                        self.finalizeTranscription(text)
                    }
                }
            }
        }

        // Audio engine for live mic input. Note: the tap was already removed
        // at the top of this function to avoid the "tap already installed"
        // crash, so we just install the new one here.
        let inputNode = audioEngine.inputNode
        let recordingFormat = validRecordingFormat(for: inputNode)
        guard let recordingFormat else {
            isListening = false
            voiceError = "Microphone input is unavailable."
            self.recognitionRequest = nil
            recognitionTask?.cancel()
            recognitionTask = nil
            return
        }

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
        hasInstalledInputTap = true

        do {
            if !audioEngine.isRunning {
                audioEngine.prepare()
                try audioEngine.start()
            }
            startLevelMonitoring()
        } catch {
            voiceError = "Could not start microphone."
            stopListening()
        }
    }

    private func validRecordingFormat(for inputNode: AVAudioInputNode) -> AVAudioFormat? {
        let outputFormat = inputNode.outputFormat(forBus: 0)
        if outputFormat.sampleRate > 0, outputFormat.channelCount > 0 {
            return outputFormat
        }

        let inputFormat = inputNode.inputFormat(forBus: 0)
        if inputFormat.sampleRate > 0, inputFormat.channelCount > 0 {
            return inputFormat
        }

        return nil
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

    func stopListening(resetFinalizing: Bool = true) {
        isListening = false
        stopLevelMonitoring()
        stopSilenceTimer()
        if resetFinalizing {
            isFinalizing = false
        }

        // CRITICAL: Remove the tap FIRST, before stopping the engine or
        // finalizing the recognition request. This prevents the tap callback
        // from firing after endAudio() and crashing.
        removeInputTapIfNeeded()

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        // Cancel the recognition task BEFORE endAudio to stop callbacks.
        // Then endAudio and nil out the request.
        isStoppingListening = recognitionTask != nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if !isConversing {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        // When conversation IS active, keep the audio session active so the
        // app doesn't get suspended by iOS when backgrounded. The .playAndRecord
        // category + audio background mode keeps the app alive.
    }

    private func removeInputTapIfNeeded() {
        guard hasInstalledInputTap else { return }
        // CRITICAL: Only remove the tap if the engine is running.
        // removeTap on a stopped engine throws an uncatchable ObjC
        // exception that crashes the app.
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        hasInstalledInputTap = false
    }

    /// Finalize the current transcription and trigger the conversation flow.
    /// Calls the onTranscriptionComplete callback to send text to the Hermes API.
    @MainActor
    func finalizeTranscription(_ text: String) {
        let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        FileLogger.shared.log("VoiceManager: finalizeTranscription called with '\(finalText)'")
        
        // Guard: if conversation ended while timer was pending, bail out
        guard isConversing else {
            FileLogger.shared.log("VoiceManager: finalizeTranscription skipped — not conversing")
            return
        }
        
        // Filter out ambient noise: don't send very short transcriptions
        // (single chars, "uh", "um", etc.) to Hermes.
        guard finalText.count >= 3 else {
            FileLogger.shared.log("VoiceManager: transcribed text too short (\(finalText.count) chars), ignoring")
            stopListening()
            // Resume listening immediately
            if isConversing {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    self?.startListening()
                }
            }
            return
        }
        
        guard !isFinalizing else {
            // Empty transcription -- just stop listening.
            // Don't auto-restart to avoid loops. User can tap mic to resume.
            FileLogger.shared.log("VoiceManager: empty or already finalizing")
            stopListening()
            return
        }

        isFinalizing = true
        voiceError = nil
        stopListening(resetFinalizing: false)

        FileLogger.shared.log("VoiceManager: remote mode finalize for '\(finalText)'")
        isThinking = true
        scheduleThinkingSafetyTimer()
        FileLogger.shared.log("VoiceManager: calling onTranscriptionComplete with '\(finalText)'")
        onTranscriptionComplete?(finalText)
        // isFinalizing will be reset when speakResponse is called
    }

    // MARK: - Silence Detection

    /// Reset the silence timer. Called whenever new transcription text arrives.
    /// If no new text arrives for `silenceTimeout` seconds, the transcription is finalized.
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.finalizeTranscription(self?.transcribedText ?? "")
            }
        }
    }

    // MARK: - Thinking safety timer

    private func scheduleThinkingSafetyTimer() {
        invalidateThinkingSafetyTimer()
        thinkingSafetyTimer = Timer.scheduledTimer(withTimeInterval: thinkingSafetyTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                FileLogger.shared.log("VoiceManager: thinking safety timer fired, isConversing=\(self.isConversing), isThinking=\(self.isThinking)")
                if self.isConversing && self.isThinking {
                    self.failRemoteTurn(message: "Hermes didn't respond in time. Try again.")
                }
            }
        }
    }

    private func invalidateThinkingSafetyTimer() {
        thinkingSafetyTimer?.invalidate()
        thinkingSafetyTimer = nil
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
            try? await Task.sleep(nanoseconds: 50_000_000)  // 0.05s (was 0.1s)
            self?.startListening()
        }
    }

    // MARK: - TTS

    /// Speak a text response using AVSpeechSynthesizer.
    /// Automatically resumes listening after speech completes.
    func speakResponse(_ text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty, isConversing else {
            return
        }

        // Voice settings are cached in instance properties and synced
        // via syncVoiceSettings() when the voice page appears.
        // Avoid reading UserDefaults on every speak call (synchronous I/O).

        isFinalizing = false
        spokenResponse = cleanText
        isSpeaking = true
        voiceError = nil

        speakWithSystemTTS(cleanText)
    }
    
    /// Speak using the system's built-in AVSpeechSynthesizer
    private func speakWithSystemTTS(_ text: String) {
        // Audio session is already configured as .playAndRecord from the
        // listening phase. Skip redundant reconfiguration to reduce latency.
        let audioSession = AVAudioSession.sharedInstance()
        if audioSession.category != .playAndRecord {
            try? audioSession.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        }

        let utterance = AVSpeechUtterance(string: text)
        // Use selected voice identifier if available, otherwise system default
        if !voiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else if let voice = VoiceDefaults.bestAvailableVoice() {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        }
        // Map slider (0.1...1.0) to AVSpeechUtterance rate range (0...1, default 0.5)
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate,
                            min(AVSpeechUtteranceMaximumSpeechRate, voiceSpeed))
        utterance.pitchMultiplier = voicePitch
        utterance.preUtteranceDelay = 0  // No dead air before speech
        utterance.postUtteranceDelay = 0.05  // Minimal gap after speech

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

    // MARK: - Voice Settings Sync

    /// Reload voice settings from UserDefaults. Call this when the voice page
    /// appears, in case the user changed settings in Settings > Voice.
    func syncVoiceSettings() {
        voiceSpeed = UserDefaults.standard.float(forKey: "voice_speed")
        if voiceSpeed == 0 { voiceSpeed = 0.5 }
        voicePitch = UserDefaults.standard.float(forKey: "voice_pitch")
        if voicePitch == 0 { voicePitch = 1.0 }
        voiceIdentifier = VoiceDefaults.ensureBestVoiceSelected()
    }

    // MARK: - Private

    func cancelRecognition() {
        isStoppingListening = recognitionTask != nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func isBenignRecognitionCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return true }

        let description = error.localizedDescription.lowercased()
        return description.contains("canceled") || description.contains("cancelled")
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
            // Minimal delay to let the audio session switch from playback to recording.
            if manager.isConversing {
                try? await Task.sleep(nanoseconds: 50_000_000)  // 0.05s
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
