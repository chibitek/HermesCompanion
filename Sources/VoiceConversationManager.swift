import Foundation
import SwiftUI
import AVFoundation
import Speech

/// Voice conversation mode for live 2-way voice interaction.
///
/// In live conversation mode:
/// 1. Records audio and transcribes via SFSpeechRecognizer (same as voice-to-text)
/// 2. Sends transcribed text to Hermes API
/// 3. Speaks the response using AVSpeechSynthesizer (iOS TTS)
///
/// This provides a natural conversation flow without requiring the Hermes API
/// to support audio input/output natively. If the API later adds audio
/// capabilities, this can be extended to use them.
@MainActor
final class VoiceConversationManager: ObservableObject {
    @Published var isConversing = false
    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var transcribedText = ""
    @Published var spokenResponse = ""
    @Published var hasPermission = false

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

    init() {
        delegateBridge.manager = self
        synthesizer.delegate = delegateBridge
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

    func startConversation(onTranscription: @escaping (String) -> Void) {
        guard hasPermission else {
            Task {
                await requestAuthorization()
                if hasPermission {
                    startConversation(onTranscription: onTranscription)
                }
            }
            return
        }

        isConversing = true
        onTranscriptionComplete = onTranscription
        startListening()
    }

    func stopConversation() {
        isConversing = false
        stopListening()
        stopSpeaking()
        onTranscriptionComplete = nil
    }

    // MARK: - Listening

    func startListening() {
        guard isConversing, !isSpeaking else { return }
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
                DispatchQueue.main.async {
                    self.transcribedText = text
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

    /// Finalize the current transcription and trigger the conversation callback.
    /// Uses a brief delay to allow the recognizer to settle on the final text.
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

        // Call the callback with the transcribed text
        // The caller will send it to Hermes and call speakResponse when the
        // reply arrives.
        onTranscriptionComplete?(finalText)
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
