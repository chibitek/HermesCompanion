import Foundation
import SwiftUI
import AVFoundation
import Speech

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
    private var activeSystemUtterance: AVSpeechUtterance?
    private var speechGeneration = UUID()

    // Conversation flow
    private var onTranscriptionComplete: ((String) -> Void)?

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
    private var recognitionRetryCount = 0

    private var remoteTurnID: UUID?
    private var ownsAudioSession = false

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
         )
#if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
          )
#endif
    }

#if os(iOS)
    /// Release audio session when app backgrounds so other apps
    /// (YouTube, Music) can play normally.
    @objc private func handleAppBackground() {
        guard isConversing else { return }
        FileLogger.shared.log("VoiceManager: app backgrounded, stopping conversation to release audio")
        stopConversation()
      }
#endif

    /// Car Bluetooth / AirPods connect or drop mid-listen: the engine stays
    /// bound to the old route and recognition errors out. Restart listening
    /// on the new route instead of dying with an error.
    /// ONLY react to real device changes — iOS also fires this notification
    /// for our own setCategory/setActive (categoryChange, routeConfigurationChange),
    /// and restarting on those kills every listen attempt at birth (Build 106 bug).
    @objc private func handleRouteChange(_ notification: Notification) {
        guard isConversing, isListening else { return }
        let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
            .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
        guard reason == .newDeviceAvailable || reason == .oldDeviceUnavailable else {
            FileLogger.shared.log("VoiceManager: route change ignored (reason=\(String(describing: reason)))")
            return
        }
        FileLogger.shared.log("VoiceManager: route change \(reason == .newDeviceAvailable ? "device added" : "device removed") — restarting listen")
        stopListening()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self,
                  self.isConversing,
                  !self.isListening,
                  !self.isSpeaking,
                  !self.isThinking
            else { return }
            self.startListening()
        }
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        // The phone and CarPlay controllers both exist during text chat. An
        // interruption from keyboard dictation or another app belongs to neither
        // idle controller; even setCategory during cleanup would change its route.
        guard ownsAudioSession else { return }
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
         case .began:
              // Interruption started — pause listening, and if not in a voice convo, also stop speaking.
             stopListening()
             if !isConversing { stopSpeaking() }
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
        FileLogger.shared.log("VoiceManager: startConversation -> startListening (hasPermission=\(hasPermission))")
        startListening()
    }

    func stopConversation() {
        remoteTurnID = nil
        pendingConversationStartID = nil
        isConversing = false
        stopListening()
        stopSpeaking()
        stopBargeInMonitoring()
        isThinking = false
        isFinalizing = false
        voiceError = nil
        onTranscriptionComplete = nil
        releaseAudioSessionIfOwned()
    }

    func beginRemoteTurn() -> UUID {
        let id = UUID()
        remoteTurnID = id
        isThinking = true
        voiceError = nil
        return id
    }

    func isCurrentRemoteTurn(_ id: UUID) -> Bool {
        isConversing && remoteTurnID == id
    }

    func completeRemoteTurn(response: String?) {
        FileLogger.shared.log("completeRemoteTurn called with response: \(String(describing: response?.prefix(120)))")
        remoteTurnID = nil
        isThinking = false
        isFinalizing = false
        
        let cleanResponse = Self.normalizedRemoteResponse(response)
        
        if cleanResponse.isEmpty {
            FileLogger.shared.log("VoiceManager: response is empty, failing turn")
            failRemoteTurn(message: "Hermes did not return a voice response.")
            return
        }
        voiceError = nil
        if isListening {
            stopListening()
        }
        speakResponse(cleanResponse)
    }
    
    // Assistant prose is authoritative. Transport status must not be inferred
    // from words that can also occur in a legitimate answer.
    nonisolated static func normalizedRemoteResponse(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Finish a remote Hermes turn when the network request fails or returns no
    /// speakable assistant message. Keep the conversation hands-free by
    /// returning to listening after the error is surfaced.
    func failRemoteTurn(message: String) {
        FileLogger.shared.log("failRemoteTurn called: \(message)")
        remoteTurnID = nil
        isThinking = false
        isFinalizing = false
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
        remoteTurnID = nil
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
        guard isConversing else { FileLogger.shared.log("VoiceManager: startListening bail — not conversing"); return }
        // If currently speaking, stop TTS first (barge-in by button tap)
        if isSpeaking {
            stopSpeaking()
        }
        guard !isThinking else { FileLogger.shared.log("VoiceManager: startListening bail — isThinking stuck"); return }
        guard !isListening else { return }  // Prevent double-start

        // Stop any lingering engine state before setting up fresh.
        // A previous session or the WakePhraseListener may have left the
        // engine running with a tap installed — the old guard checked
        // isRunning+hasTap BEFORE the stop code, so it silently returned
        // and the mic never activated.
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        removeInputTapIfNeeded()
        guard let speechRecognizer, speechRecognizer.isAvailable,
              speechRecognizer.supportsOnDeviceRecognition else {
            FileLogger.shared.log("VoiceManager: startListening bail — recognizer unavailable (nil: \(speechRecognizer == nil))")
            voiceError = "On-device speech recognition is unavailable for this language."
            return
        }
        isStoppingListening = false
        voiceError = nil

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
            ownsAudioSession = true
        } catch {
            isListening = false
            FileLogger.shared.log("VoiceManager: audio session activation failed: \(error.localizedDescription)")
            // Transient contention (route change, another session settling) —
            // bounded retry, same pattern as recognition errors.
            recognitionRetryCount += 1
            if isConversing && recognitionRetryCount <= 3 {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard let self, self.isConversing, !self.isListening,
                          !self.isSpeaking, !self.isThinking else { return }
                    self.startListening()
                }
            } else {
                recognitionRetryCount = 0
                voiceError = "Microphone unavailable: \(error.localizedDescription)"
            }
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
        recognitionRequest.requiresOnDeviceRecognition = true

        // Recognition task with final result detection
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                // A canceled recognizer may report after a replacement has started.
                guard self.recognitionRequest === recognitionRequest else { return }

                if let error {
                    if self.isStoppingListening || self.isBenignRecognitionCancellation(error) {
                        self.isStoppingListening = false
                        if !self.isFinalizing {
                            self.stopListening()
                        }
                        return
                    }

                    FileLogger.shared.log("VoiceManager: recognition error: \(error.localizedDescription)")
                    self.stopListening()
                    // Auto-recover transient errors (network blips with
                    // server-based recognition, Bluetooth route changes)
                    // instead of leaving the mic dead until a manual tap.
                    self.recognitionRetryCount += 1
                    if self.isConversing && self.recognitionRetryCount <= 3 {
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
                    } else {
                        self.recognitionRetryCount = 0
                        self.voiceError = "Speech recognition stopped: \(error.localizedDescription). Restart voice mode to retry."
                    }
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
            voiceError = "The audio input reported no usable recording format. Reconnect your headset or use the phone microphone, then restart voice mode."
            FileLogger.shared.log("VoiceManager: startListening bail — invalid recording format (sampleRate 0 / route stuck)")
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
            FileLogger.shared.log("VoiceManager: audio engine start failed: \(error.localizedDescription)")
            voiceError = "Could not start the microphone: \(error.localizedDescription). Stop voice mode, check the selected audio input, and retry."
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

    private var lastLevelPublish: TimeInterval = 0

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
        // ponytail: throttle @Published churn — tap fires ~43Hz, UI only needs ~15Hz
        let now = CACurrentMediaTime()
        guard now - lastLevelPublish > 0.06, abs(level - audioLevel) > 0.02 else { return }
        lastLevelPublish = now
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

        if !isConversing && !isSpeaking { releaseAudioSessionIfOwned() }
        // Active voice turns retain ownership between listening and speaking.
    }

    private func releaseAudioSessionIfOwned() {
        guard ownsAudioSession else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        ownsAudioSession = false
    }

    private func removeInputTapIfNeeded() {
        guard hasInstalledInputTap else { return }
        // Taps remain installed when an interruption stops the engine.
        audioEngine.inputNode.removeTap(onBus: 0)
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
        recognitionRetryCount = 0
        voiceError = nil
        stopListening(resetFinalizing: false)

        FileLogger.shared.log("VoiceManager: remote mode finalize for '\(finalText)'")
        isThinking = true
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

        stopSpeaking()
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
        let session = AVAudioSession.sharedInstance()
        if !ownsAudioSession || session.category != .playAndRecord {
            do {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
                ownsAudioSession = true
            } catch {
                isSpeaking = false
                voiceError = "Could not start voice playback: \(error.localizedDescription)"
                return
            }
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

        registerSystemUtterance(utterance)
        synthesizer.speak(utterance)

        // Start monitoring mic for barge-in (user interrupting the AI)
        startBargeInMonitoring()
    }
    
    func stopSpeaking() {
        speechGeneration = UUID()
        activeSystemUtterance = nil
        stopBargeInMonitoring()
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    func registerSystemUtterance(_ utterance: AVSpeechUtterance) {
        speechGeneration = UUID()
        activeSystemUtterance = utterance
    }

    func systemSpeechDidStart(_ utterance: AVSpeechUtterance) {
        guard isConversing, activeSystemUtterance === utterance else { return }
        isSpeaking = true
    }

    func systemSpeechDidEnd(_ utterance: AVSpeechUtterance, resumeListening: Bool) async {
        guard activeSystemUtterance === utterance else { return }
        let generation = speechGeneration
        activeSystemUtterance = nil
        isSpeaking = false
        stopBargeInMonitoring()
        guard resumeListening, isConversing else { return }
        do {
            try await Task.sleep(nanoseconds: 50_000_000)
        } catch { return }
        // A stop, replacement reply, or new conversation owns subsequent audio.
        guard generation == speechGeneration, isConversing,
              !isSpeaking, !isListening, !isThinking else { return }
        startListening()
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
            manager?.systemSpeechDidStart(utterance)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            await manager?.systemSpeechDidEnd(utterance, resumeListening: true)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            await manager?.systemSpeechDidEnd(utterance, resumeListening: false)
        }
    }
}
