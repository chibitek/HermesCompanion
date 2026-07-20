import Foundation

enum VoiceEndpointingPolicy {
    /// Natural conversation includes short thinking pauses. Anything below a
    /// second aggressively fragments speech into separate turns.
    /// 1.5s is the floor of the natural-pause band (test asserts >= 1.5).
    static let silenceTimeout: TimeInterval = 1.5
}

enum WakePhraseParser {
    static func containsWakePhrase(_ transcription: String) -> Bool {
        let words = transcription
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard words.count >= 2 else { return false }
        return zip(words, words.dropFirst()).contains { first, second in
            first == "hey" && second == "hermes"
        }
    }
}
