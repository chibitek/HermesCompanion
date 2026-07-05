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

    // Local LLM
    let localLLM = LocalLLMManager()

    // Speech recognition
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // TTS
    private let synthesizer = AVSpeechSynthesizer()
    private let delegateBridge = SpeechDelegateBridge()

    // Conversation flow
    private var onTranscriptionComplete: ((String) -> Void)?
    private var onLocalResponse: ((String) -> Void)?

    init() {
        delegateBridge.manager = self
        synthesizer.delegate = delegateBridge

        // Auto-select local mode if available, otherwise remote
        if localLLM.isAvailable {
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
            AVAudioSession.sharedInstance().requestRecordPermission { _ in
                continuation.resume()
            }
        }

        // Speech recognition
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in
                continuation.resume()
            }
        }

        let micGranted = AVAudioSession.sharedInstance().recordPermission == .granted
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
        isThinking = false
        onTranscriptionComplete = nil
        onLocalResponse = nil
    }

    // MARK: - Listening

    func startListening() {
        guard isConversing, !isSpeaking, !isThinking else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

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
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        if #available(iOS 16, *) {
            recognitionRequest.addsPunctuation = true
        }

        // Recognition task with final result detection
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                self.stopListening()
                return
            }

            if let result = result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor [weak self] in
                    self?.transcribedText = text
                }

                // When the recognizer is fairly confident the user paused,
                // finalize and send the transcription.
                if result.isFinal {
                    self.finalizeTranscription(text)
                }
            }
        }

        // Audio engine for live mic input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, let recognitionRequest = self.recognitionRequest else { return }
            recognitionRequest.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            stopListening()
        }
    }

    func stopListening() {
        isListening = false

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
        guard !finalText.isEmpty else {
            stopListening()
            if isConversing {
                // Restart listening after a brief pause
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.startListening()
                }
            }
            return
        }

        stopListening()

        switch conversationMode {
        case .local:
            // Generate response on-device, then speak it
            isThinking = true
            Task {
                let response = await localLLM.generateResponse(to: finalText)
                isThinking = false
                if isConversing {
                    speakResponse(response)
                    onLocalResponse?(response)
                }
            }

        case .remote:
            // Call the callback with the transcribed text
            // The caller will send it to Hermes and call speakResponse when the
            // reply arrives.
            onTranscriptionComplete?(finalText)
        }
    }

    // MARK: - TTS

    /// Speak a text response using AVSpeechSynthesizer.
    /// Automatically resumes listening after speech completes.
    func speakResponse(_ text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty, isConversing else { return }

        spokenResponse = cleanText
        isSpeaking = true

        // Configure audio session for playback
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            // Continue anyway — TTS may still work
        }

        let utterance = AVSpeechUtterance(string: cleanText)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.3

        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
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
            // Resume listening after the response is spoken
            if manager.isConversing {
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
