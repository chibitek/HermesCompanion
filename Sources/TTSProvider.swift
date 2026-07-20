import Foundation
import Security

/// TTS provider for voice replies. All providers are listed in Settings
/// regardless of key availability; ones with a stored key show a green dot.
enum TTSProvider: String, CaseIterable, Identifiable {
    case apple
    case elevenlabs
    case openai
    case cartesia
    case mistral

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: return "Apple (on-device)"
        case .elevenlabs: return "ElevenLabs"
        case .openai: return "OpenAI TTS"
        case .cartesia: return "Cartesia Sonic"
        case .mistral: return "Mistral Voxtral"
        }
    }

    /// Providers with a working speak path today. Others fall back to Apple.
    var isImplemented: Bool {
        switch self {
        case .apple, .elevenlabs: return true
        case .openai, .cartesia, .mistral: return false
        }
    }

    /// Apple TTS needs no key and is always live.
    var hasKey: Bool {
        self == .apple || TTSKeyStore.load(provider: self) != nil
    }

    var isLive: Bool { hasKey && isImplemented }

    static let selectedKey = "tts_provider"
    static var selected: TTSProvider {
        get {
            TTSProvider(rawValue: UserDefaults.standard.string(forKey: selectedKey) ?? "") ?? .apple
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: selectedKey) }
    }
}

/// Minimal Keychain read/write for TTS API keys, one item per provider.
enum TTSKeyStore {
    private static func account(_ provider: TTSProvider) -> String { "tts_key_\(provider.rawValue)" }

    static func load(provider: TTSProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.chibitek.hermescompanion.tts",
            kSecAttrAccount as String: account(provider),
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String, provider: TTSProvider) {
        let data = Data(key.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.chibitek.hermescompanion.tts",
            kSecAttrAccount as String: account(provider),
        ]
        SecItemDelete(base as CFDictionary)
        var attrs = base
        attrs[kSecValueData as String] = data
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func delete(provider: TTSProvider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.chibitek.hermescompanion.tts",
            kSecAttrAccount as String: account(provider),
        ]
        SecItemDelete(query as CFDictionary)
    }
}
