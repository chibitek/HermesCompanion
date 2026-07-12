import Foundation

struct ActiveSessionPersistence {
    private let defaults: UserDefaults
    private let keyPrefix = "active_session."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(sessionID: String, for baseURL: String) {
        defaults.set(sessionID, forKey: key(for: baseURL))
    }

    func load(for baseURL: String) -> String? {
        defaults.string(forKey: key(for: baseURL))
    }

    func clear(for baseURL: String) {
        defaults.removeObject(forKey: key(for: baseURL))
    }

    private func key(for baseURL: String) -> String {
        keyPrefix + normalized(baseURL)
    }

    private func normalized(_ baseURL: String) -> String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
