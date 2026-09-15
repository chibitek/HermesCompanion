import Foundation

enum ComposerDictationLogic {
    static func mergedText(original: String, transcription: String) -> String {
        let spoken = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return original }
        guard !original.isEmpty else { return spoken }
        return original + (original.last?.isWhitespace == true ? "" : " ") + spoken
    }
}

enum ComposerSubmissionAction: Equatable {
    case send
    case queue
    case compose
}

enum ComposerSubmissionLogic {
    static func action(isStreaming: Bool, canSend: Bool) -> ComposerSubmissionAction {
        if isStreaming {
            return canSend ? .queue : .compose
        }
        return canSend ? .send : .compose
    }
}
