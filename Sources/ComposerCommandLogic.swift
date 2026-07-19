import Foundation

enum ComposerSubmissionAction: Equatable {
    case send
    case queue
    case stop
    case voice
}

enum ComposerSubmissionLogic {
    static func action(isStreaming: Bool, canSend: Bool) -> ComposerSubmissionAction {
        if isStreaming {
            return canSend ? .queue : .stop
        }
        return canSend ? .send : .voice
    }
}
