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

enum SkillPickerLayout {
    /// Keeps the composer visible while giving the skill browser most of the screen.
    static func maximumHeight(availableHeight: Double) -> Double {
        max(280, min(600, availableHeight - 160))
    }
}
