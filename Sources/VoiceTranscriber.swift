import Foundation
import SwiftUI
import Speech
import AVFoundation

/// On-device voice-to-text transcription using SFSpeechRecognizer.
///
/// Usage:
/// 1. Call startTranscription() to request permission and begin recording.
/// 2. Observe `transcribedText` for live results.
/// 3. Call stopTranscription() to stop or cancel a pending start.
@MainActor
final class VoiceTranscriber: ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var hasPermission = false
    @Published var errorMessage: String?

    // SFSpeechRecognizer fallback (works on all iOS versions)
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var hasInputTap = false
    private var recordingID: UUID?

    func requestAuthorization() async {
        // Request microphone permission
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            AVAudioApplication.requestRecordPermission { _ in
                continuation.resume()
            }
        }

        // Request speech recognition permission
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in
                continuation.resume()
            }
        }

        // Check if we have both permissions
        let micGranted = AVAudioApplication.shared.recordPermission == .granted
        let speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        hasPermission = micGranted && speechGranted
    }

    func startTranscription() {
        stopTranscription()
        transcribedText = ""
        let recordingID = UUID()
        self.recordingID = recordingID
        errorMessage = nil
        guard hasPermission else {
            Task {
                await requestAuthorization()
                guard self.recordingID == recordingID else { return }
                if hasPermission {
                    startTranscription()
                } else {
                    errorMessage = "Microphone and speech recognition permissions are required."
                }
            }
            return
        }

        guard let speechRecognizer, speechRecognizer.isAvailable,
              speechRecognizer.supportsOnDeviceRecognition else {
            errorMessage = "On-device speech recognition is unavailable for this language."
            return
        }

        isRecording = true

        // Configure audio session for recording
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try? audioSession.setPreferredSampleRate(44_100)
            try? audioSession.setPreferredInputNumberOfChannels(1)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Could not activate the microphone: \(error.localizedDescription)"
            stopTranscription()
            return
        }

        // Set up recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true
        recognitionRequest.requiresOnDeviceRecognition = true
        recognitionRequest.taskHint = .dictation

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.recordingID == recordingID else { return }
                if let text { self.transcribedText = text }
                if let errorDescription {
                    self.errorMessage = errorDescription
                    self.stopTranscription()
                } else if isFinal {
                    self.stopTranscription()
                }
            }
        }

        // Set up audio engine for live microphone input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            errorMessage = "No microphone input is available."
            stopTranscription()
            return
        }

        // ponytail: guard against double installTap — ObjC exception is uncatchable.
        // A tap can outlive the engine (iOS stops the engine in background), so
        // track it with a flag instead of checking audioEngine.isRunning.
        if hasInputTap {
            inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        hasInputTap = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            errorMessage = "Could not start the microphone: \(error.localizedDescription)"
            stopTranscription()
        }
    }

    func stopTranscription() {
        recordingID = nil
        let wasRecording = isRecording || hasInputTap || recognitionTask != nil
        isRecording = false

        // Remove the tap whenever one is installed (flag-tracked): a tap can
        // outlive the engine when iOS stops it in the background, and a leaked
        // tap makes the next installTap throw an uncatchable ObjC exception.
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        guard wasRecording else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
     }

}
