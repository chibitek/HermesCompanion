import Foundation

/// Pure parsing and filtering used by the chat composer skill picker.
enum SkillCommandLogic {
    static func shouldShowSuggestions(for text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"), !trimmed.contains("\n") else { return false }

        if trimmed == "/" || trimmed == "/skill" || text.hasPrefix("/skill ") {
            return true
        }

        // A single leading slash followed by a search term is a shortcut for
        // finding skills, for example `/swift`.
        return !String(trimmed.dropFirst()).contains(" ")
    }

    static func suggestions(for text: String, skills: [Skill]) -> [Skill] {
        guard shouldShowSuggestions(for: text) else { return [] }
        let query = searchQuery(from: text)

        let matches = skills.filter { skill in
            guard !query.isEmpty else { return true }
            return skill.name.localizedCaseInsensitiveContains(query)
                || (skill.description ?? "").localizedCaseInsensitiveContains(query)
                || (skill.category ?? "").localizedCaseInsensitiveContains(query)
        }

        return matches.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func textBySelecting(_ skill: Skill, currentText: String) -> String {
        "/skill \(skill.name) "
    }

    /// The API session endpoints accept chat turns, not gateway slash-command
    /// dispatch. Convert the explicit command into a deterministic instruction
    /// that makes the agent load the installed skill through its skills tools.
    static func messagePayload(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/skill ") else { return text }

        let remainder = String(trimmed.dropFirst("/skill ".count))
        let pieces = remainder.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard let skillPart = pieces.first, !skillPart.isEmpty else { return text }

        let skillName = String(skillPart)
        let activation = "Use the installed skill named \"\(skillName)\" for this request. Load it before acting and follow its instructions."
        guard pieces.count == 2 else { return activation }

        let request = String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        return request.isEmpty ? activation : "\(activation)\n\n\(request)"
    }

    private static func searchQuery(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "/" || trimmed == "/skill" { return "" }
        if trimmed.hasPrefix("/skill ") {
            return String(trimmed.dropFirst("/skill ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(trimmed.dropFirst())
    }
}
