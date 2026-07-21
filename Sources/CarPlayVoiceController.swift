import Foundation
import Combine

/// Voice-first controller for CarPlay. Owns its own VoiceConversationManager
/// (the in-app one is scoped to ChatView) and drives turns through AppStore.
@MainActor
final class CarPlayVoiceController: ObservableObject {
    static let shared = CarPlayVoiceController()

    @Published private(set) var stateText = "Tap to talk"
    @Published private(set) var lastTranscription = ""
    @Published private(set) var lastResponse = ""
    @Published private(set) var isActive = false

    let voice = VoiceConversationManager()
    private weak var store: AppStore?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Keep CarPlay UI in sync with the voice manager's state.
        voice.$isListening
            .combineLatest(voice.$isThinking, voice.$isSpeaking, voice.$voiceError)
            .receive(on: RunLoop.main)
            .sink { [weak self] listening, thinking, speaking, error in
                guard let self else { return }
                if let error, !error.isEmpty {
                    self.stateText = error
                } else if thinking {
                    self.stateText = "Thinking..."
                } else if speaking {
                    self.stateText = "Speaking..."
                } else if listening {
                    self.stateText = "Listening..."
                } else {
                    self.stateText = "Tap to talk"
                }
            }
            .store(in: &cancellables)

        voice.$transcribedText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                guard let self, !text.isEmpty else { return }
                self.lastTranscription = text
            }
            .store(in: &cancellables)
    }

    /// Called from HermesCompanionApp once the store exists.
    func attach(store: AppStore) {
        self.store = store
        voice.onStopBackgroundAudio = { [weak store] in
            store?.stopSilentAudioForVoice()
        }
    }

    func toggleConversation() {
        if isActive {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard let store, store.isConnected else {
            stateText = "Not connected to Hermes"
            return
        }
        isActive = true
        voice.startConversation { [weak self] transcription in
            self?.handleTranscription(transcription)
        }
    }

    func stop() {
        isActive = false
        voice.stopConversation()
        stateText = "Tap to talk"
    }

    private func handleTranscription(_ transcription: String) {
        guard let store else { return }
        let priorErrorID = store.error?.id
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.voice.isThinking = true

            // 60s hard timeout. do/catch, never try? — see ios-voice skill.
            let timeoutTask = Task {
                do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, self.voice.isThinking else { return }
                    self.voice.failRemoteTurn(message: "Hermes took too long to respond.")
                }
            }

            let responseMessage = await store.sendMessage(transcription, skipPostReload: true)
            timeoutTask.cancel()

            guard self.voice.isThinking else { return }  // turn already ended
            guard let responseMessage else {
                if let error = store.error, error.id != priorErrorID {
                    self.voice.failRemoteTurn(message: error.message)
                } else {
                    self.voice.failRemoteTurn(message: "Hermes did not respond.")
                }
                return
            }
            let response = responseMessage.content
            if response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.voice.failRemoteTurn(message: "Hermes returned an empty response.")
            } else {
                self.lastResponse = response
                self.voice.completeRemoteTurn(response: response)
            }
        }
    }
}
