import Foundation
import SwiftUI
import AVFoundation
import Speech
import Network

/// Voice conversation mode: local (on-device), remote (Hermes API), or premium (cloud TTS services).
enum ConversationMode: String, CaseIterable {
    case local = "Local"
    case remote = "Remote"
    case premium = "Premium"

    var icon: String {
        switch self {
        case .local: return "iphone.radiowaves.left.and.right"
        case .remote: return "cloud.fill"
        case .premium: return "sparkles"
        }
    }

    var toggled: ConversationMode {
        switch self {
        case .local: return .remote
        case .remote: return .premium
        case .premium: return .local
        }
    }
    
    var displayName: String {
        switch self {
        case .local: return "On-Device"
        case .remote: return "Hermes Server"
        case .premium: return "Cloud TTS"
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
    @Published var voiceError: String?

    // Voice settings (persisted via @AppStorage in VoiceSettingsView)
    var voiceSpeed: Float = 0.5
    var voicePitch: Float = 1.0
    var voiceIdentifier: String = ""
    var premiumVoiceService: PremiumVoiceService = .amazonPolly
    var premiumVoiceName: String = "Joanna"
    var premiumVoiceSpeed: Double = 1.0
    var premiumVoicePitch: Double = 1.0

    // Local LLM
    let localLLM = LocalLLMManager()

    // Speech recognition
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var hasInstalledInputTap = false
    private var isStoppingListening = false

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
    private let silenceTimeout: TimeInterval = 0.8  // Faster finalization after user stops
    private var lastTranscriptionTime: Date = .distantPast
    private var lastTranscribedText: String = ""

    // Debounce for finalization
    private var isFinalizing = false
    private var pendingConversationStartID: UUID?

    // Safety net: if thinking lasts too long, cancel and resume listening.
    // Uses 90 seconds so slow models / long tool runs aren't prematurely killed.
    private var thinkingSafetyTimer: Timer?
    private let thinkingSafetyTimeout: TimeInterval = 90

    init() {
        delegateBridge.manager = self
        synthesizer.delegate = delegateBridge

        // Load voice settings from UserDefaults (set via Settings > Voice)
        voiceSpeed = UserDefaults.standard.float(forKey: "voice_speed")
        if voiceSpeed == 0 { voiceSpeed = 0.5 }
        voicePitch = UserDefaults.standard.float(forKey: "voice_pitch")
        if voicePitch == 0 { voicePitch = 1.0 }
        voiceIdentifier = VoiceDefaults.ensureBestVoiceSelected()
        
        // Load premium voice settings
        let premiumServiceRaw = UserDefaults.standard.string(forKey: "premium_voice_service") ?? PremiumVoiceService.amazonPolly.rawValue
        premiumVoiceService = PremiumVoiceService(rawValue: premiumServiceRaw) ?? .amazonPolly
        premiumVoiceName = UserDefaults.standard.string(forKey: "premium_voice_name") ?? "Joanna"
        premiumVoiceSpeed = UserDefaults.standard.double(forKey: "premium_voice_speed")
        if premiumVoiceSpeed == 0 { premiumVoiceSpeed = 1.0 }
        premiumVoicePitch = UserDefaults.standard.double(forKey: "premium_voice_pitch")
        if premiumVoicePitch == 0 { premiumVoicePitch = 1.0 }

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
            selector: #selector(handleAudioSessionInterruption),
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
        } else if isHermesConnected {
            conversationMode = .remote
        } else {
            // Check if we have network connectivity for premium mode
            Task {
                let isConnected = await hasNetworkConnectivity()
                DispatchQueue.main.async {
                    if isConnected {
                        // We could default to premium mode if network is available
                        // But for now, we'll stick with remote as the default
                        self.conversationMode = .remote
                    } else {
                        self.conversationMode = .remote
                    }
                }
            }
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
            let startID = UUID()
            pendingConversationStartID = startID
            Task {
                await requestAuthorization()
                guard pendingConversationStartID == startID else { return }
                if hasPermission {
                    startConversation(
                        onTranscription: onTranscription,
                        onLocalResponse: onLocalResponse
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
        self.onLocalResponse = onLocalResponse
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
        onLocalResponse = nil
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
            print("Response is empty after filtering, failing turn")
            failRemoteTurn(message: "Hermes did not return a voice response.")
            return
        }
        voiceError = nil
        stopListening()
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

        // Safety net: always speak the error so the user isn't left staring at the screen.
        speakResponse(message)

        guard isConversing else { return }
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

    // MARK: - Listening

    func startListening() {
        guard isConversing else { return }
        // If currently speaking, stop TTS first (barge-in by button tap)
        if isSpeaking {
            stopSpeaking()
        }
        guard !isThinking else { return }
        guard !isListening else { return }  // Prevent double-start
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            voiceError = "Speech recognition is unavailable."
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
        if #available(iOS 16, *) {
            recognitionRequest.addsPunctuation = true
        }
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

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        removeInputTapIfNeeded()

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        isStoppingListening = recognitionTask != nil
        recognitionTask?.cancel()
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func removeInputTapIfNeeded() {
        guard hasInstalledInputTap else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        hasInstalledInputTap = false
    }

    /// Finalize the current transcription and trigger the conversation flow.
    /// In local mode: generates a response via LocalLLMManager, speaks it, resumes listening.
    /// In remote mode: calls the onTranscriptionComplete callback.
    @MainActor
    func finalizeTranscription(_ text: String) {
        let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        FileLogger.shared.log("VoiceManager: finalizeTranscription called with '\(finalText)'")
        
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
            print("VoiceManager: empty or already finalizing")
            stopListening()
            return
        }

        isFinalizing = true
        voiceError = nil
        stopListening(resetFinalizing: false)

        switch conversationMode {
        case .local:
            isThinking = true
            invalidateThinkingSafetyTimer()
            Task {
                let response = await localLLM.generateResponse(to: finalText)
                await MainActor.run {
                    isThinking = false
                    isFinalizing = false
                }
                if isConversing {
                    speakResponse(response)
                    onLocalResponse?(response)
                }
            }

        case .remote:
            FileLogger.shared.log("VoiceManager: remote mode finalize for '\(finalText)'")
            isThinking = true
            FileLogger.shared.log("VoiceManager: remote mode, calling onTranscriptionComplete with '\(finalText)'")
            print("VoiceManager: remote mode, calling onTranscriptionComplete with '\(finalText)'")
            onTranscriptionComplete?(finalText)
            // For remote mode, isFinalizing will be reset when speakResponse is called

        case .premium:
            FileLogger.shared.log("VoiceManager: premium mode finalize for '\(finalText)'")
            // For premium mode, we still send to Hermes but speak with premium TTS
            isThinking = true
            FileLogger.shared.log("VoiceManager: premium mode, calling onTranscriptionComplete with '\(finalText)'")
            print("VoiceManager: premium mode, calling onTranscriptionComplete with '\(finalText)'")
            onTranscriptionComplete?(finalText)
            // For premium mode, isFinalizing will be reset when speakResponse is called
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
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s (was 0.2s)
            self?.startListening()
        }
    }

    // MARK: - TTS

    /// Speak a text response using AVSpeechSynthesizer or premium cloud TTS services.
    /// Automatically resumes listening after speech completes.
    func speakResponse(_ text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty, isConversing else { 
            print("Not speaking response - empty text or not conversing")
            return 
        }

        print("SpeakResponse called with text: \(cleanText)")
        print("Conversation mode: \(conversationMode)")
        print("Is conversing: \(isConversing)")

        // Sync voice settings from UserDefaults
        voiceSpeed = UserDefaults.standard.float(forKey: "voice_speed")
        voicePitch = UserDefaults.standard.float(forKey: "voice_pitch")
        voiceIdentifier = VoiceDefaults.ensureBestVoiceSelected()
        if voiceSpeed == 0 { voiceSpeed = 0.5 }
        if voicePitch == 0 { voicePitch = 1.0 }
        
        // Sync premium voice settings
        let premiumServiceRaw = UserDefaults.standard.string(forKey: "premium_voice_service") ?? PremiumVoiceService.amazonPolly.rawValue
        premiumVoiceService = PremiumVoiceService(rawValue: premiumServiceRaw) ?? .amazonPolly
        premiumVoiceName = UserDefaults.standard.string(forKey: "premium_voice_name") ?? "Joanna"
        premiumVoiceSpeed = UserDefaults.standard.double(forKey: "premium_voice_speed")
        if premiumVoiceSpeed == 0 { premiumVoiceSpeed = 1.0 }
        premiumVoicePitch = UserDefaults.standard.double(forKey: "premium_voice_pitch")
        if premiumVoicePitch == 0 { premiumVoicePitch = 1.0 }

        isFinalizing = false
        spokenResponse = cleanText
        isSpeaking = true
        voiceError = nil

        // Handle different conversation modes
        switch conversationMode {
        case .local, .remote:
            // Use system TTS for local and remote modes
            print("Using system TTS")
            speakWithSystemTTS(cleanText)
        case .premium:
            // Use premium cloud TTS services
            print("Using premium TTS")
            speakWithPremiumTTS(cleanText)
        }
    }
    
    /// Speak using the system's built-in AVSpeechSynthesizer
    private func speakWithSystemTTS(_ text: String) {
        // Configure audio session for playback + recording (for barge-in)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            // Continue anyway -- TTS may still work
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
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.3

        // Add debug logging
        print("Speaking text: \(text)")
        print("Voice identifier: \(voiceIdentifier)")
        print("Voice: \(String(describing: utterance.voice))")
        print("Rate: \(utterance.rate)")
        print("Pitch: \(utterance.pitchMultiplier)")

        synthesizer.speak(utterance)

        // Start monitoring mic for barge-in (user interrupting the AI)
        startBargeInMonitoring()
    }
    
    /// Speak using premium cloud TTS services (Amazon Polly or Google Cloud TTS)
    private func speakWithPremiumTTS(_ text: String) {
        // For now, we'll simulate premium TTS by using system TTS with enhanced settings
        // In a real implementation, this would make API calls to the cloud services
        
        // Configure audio session for playback + recording (for barge-in)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            // Continue anyway -- TTS may still work
        }

        let utterance = AVSpeechUtterance(string: text)
        
        // Use premium voice settings
        // Map premium speed (0.25...2.0) to AVSpeechUtterance rate range (0...1, default 0.5)
        let mappedSpeed = Float(premiumVoiceSpeed * 0.5) // Scale to fit within system TTS range
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate,
                            min(AVSpeechUtteranceMaximumSpeechRate, mappedSpeed))
        utterance.pitchMultiplier = Float(premiumVoicePitch)
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.3

        // Try to find a premium-quality voice if available
        if let voice = findPremiumQualityVoice() {
            utterance.voice = voice
        } else {
            // Fallback to system voice
            if !voiceIdentifier.isEmpty,
               let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
                utterance.voice = voice
            } else if let voice = VoiceDefaults.bestAvailableVoice() {
                utterance.voice = voice
            } else {
                utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            }
        }

        // Add debug logging
        print("Speaking text with premium TTS: \(text)")
        print("Premium voice service: \(premiumVoiceService)")
        print("Premium voice name: \(premiumVoiceName)")
        print("Premium voice: \(String(describing: utterance.voice))")
        print("Rate: \(utterance.rate)")
        print("Pitch: \(utterance.pitchMultiplier)")

        synthesizer.speak(utterance)

        // Start monitoring mic for barge-in (user interrupting the AI)
        startBargeInMonitoring()
    }
    
    /// Find a premium-quality voice that matches the selected service
    private func findPremiumQualityVoice() -> AVSpeechSynthesisVoice? {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        
        // Filter for premium quality voices
        let premiumVoices = allVoices.filter { $0.quality == .premium }
        
        // If we have premium voices, try to find one that matches our settings
        if !premiumVoices.isEmpty {
            // Try to find a voice with a name that matches our premium voice name
            if let matchingVoice = premiumVoices.first(where: { 
                $0.name.localizedCaseInsensitiveContains(premiumVoiceName) 
            }) {
                return matchingVoice
            }
            
            // Fallback to the first premium voice
            return premiumVoices.first
        }
        
        // No premium voices available, return nil to use fallback
        return nil
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
        // If switching to premium mode, ensure we have network connectivity
        if conversationMode == .premium {
            Task {
                let isConnected = await hasNetworkConnectivity()
                if !isConnected {
                    // Fallback to remote mode if no network connectivity
                    DispatchQueue.main.async {
                        self.conversationMode = .remote
                        self.voiceError = "No internet connection. Switched to remote mode."
                    }
                }
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
        voiceIdentifier = VoiceDefaults.ensureBestVoiceSelected()
        
        // Sync premium voice settings
        let premiumServiceRaw = UserDefaults.standard.string(forKey: "premium_voice_service") ?? PremiumVoiceService.amazonPolly.rawValue
        premiumVoiceService = PremiumVoiceService(rawValue: premiumServiceRaw) ?? .amazonPolly
        premiumVoiceName = UserDefaults.standard.string(forKey: "premium_voice_name") ?? "Joanna"
        premiumVoiceSpeed = UserDefaults.standard.double(forKey: "premium_voice_speed")
        if premiumVoiceSpeed == 0 { premiumVoiceSpeed = 1.0 }
        premiumVoicePitch = UserDefaults.standard.double(forKey: "premium_voice_pitch")
        if premiumVoicePitch == 0 { premiumVoicePitch = 1.0 }
    }

    /// Sync voice settings from @AppStorage values stored in the voice page.
    func updateVoiceSettings(speed: Float, pitch: Float, identifier: String, premiumService: PremiumVoiceService, premiumVoiceName: String, premiumSpeed: Double, premiumPitch: Double) {
        voiceSpeed = speed
        voicePitch = pitch
        voiceIdentifier = identifier
        self.premiumVoiceService = premiumService
        self.premiumVoiceName = premiumVoiceName
        self.premiumVoiceSpeed = premiumSpeed
        self.premiumVoicePitch = premiumPitch
    }
    
    // MARK: - Network Connectivity
    
    /// Check if device has internet connectivity
    func hasNetworkConnectivity() async -> Bool {
        return await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "NetworkMonitor")
            
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.status == .satisfied)
            }
            
            monitor.start(queue: queue)
        }
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
            // Add a small delay to let the audio session settle.
            if manager.isConversing {
                try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s — let the audio session settle before restarting the engine
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
