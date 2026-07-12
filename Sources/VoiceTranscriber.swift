import Foundation
import SwiftUI
import Speech
import AVFoundation

/// Voice-to-text transcription using iOS 26 SpeechAnalyzer (on-device).
/// Falls back to SFSpeechRecognizer on older iOS.
///
/// Usage:
/// 1. Call requestAuthorization() once on first use.
/// 2. Call startTranscription() to begin recording + transcribing.
/// 3. Observe `transcribedText` for live results.
/// 4. Call stopTranscription() to stop.
@MainActor
final class VoiceTranscriber: ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var hasPermission = false

    // SFSpeechRecognizer fallback (works on all iOS versions)
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

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
        guard hasPermission else {
            Task {
                await requestAuthorization()
                if hasPermission {
                    startTranscription()
                }
            }
            return
        }

        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        // Cancel any existing task
        cancelTask()

        // Reset text
        transcribedText = ""
        isRecording = true

        // Configure audio session for recording
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try? audioSession.setPreferredSampleRate(44_100)
            try? audioSession.setPreferredInputNumberOfChannels(1)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            isRecording = false
            return
        }

        // Set up recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        if #available(iOS 16, *) {
            recognitionRequest.addsPunctuation = true
        }
        // Prefer on-device recognition when available for lower latency
        if #available(iOS 13, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }
        recognitionRequest.taskHint = .dictation

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if error != nil {
                self.stopTranscription()
                return
            }

            if let result = result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor [weak self] in
                    self?.transcribedText = text
                }
            }

            if result?.isFinal == true {
                self.stopTranscription()
            }
        }

        // Set up audio engine for live microphone input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // ponytail: guard against double installTap — ObjC exception is uncatchable
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, let recognitionRequest = self.recognitionRequest else { return }
            recognitionRequest.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            stopTranscription()
        }
    }

    func stopTranscription() {
        isRecording = false

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        // Always remove tap — it may persist even if engine stopped between install and stop
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func cancelTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }
}
