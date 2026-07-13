import Foundation

/// Shared provider/model utility functions used across multiple views.
enum ProviderUtils {

    /// Extract provider prefix from a model ID (e.g. "openai/gpt-4" -> "openai").
    /// Returns nil for model IDs without a slash.
    static func providerOf(_ model: String) -> String? {
        guard let slash = model.firstIndex(of: "/"), slash > model.startIndex else { return nil }
        return String(model[..<slash])
    }

    /// Shorten a model name by taking the part after the last slash.
    static func shortModelName(_ model: String) -> String {
        if model.contains("/") {
            return model.split(separator: "/").last.map { String($0) } ?? model
        }
        return model
    }

    /// Human-readable name for a provider slug.
    static func displayName(for provider: String) -> String {
        switch provider.lowercased() {
        case "openrouter": return "OpenRouter"
        case "ollama", "ollama-local": return "Ollama (local)"
        case "ollama-cloud": return "Ollama Cloud"
        case "opencode-zen": return "OpenCode Zen"
        case "opencode-go": return "OpenCode Go"
        case "openai", "openai-api": return "OpenAI"
        case "codex-oauth", "openai-codex": return "OpenAI Codex"
        case "github-copilot", "copilot": return "GitHub Copilot"
        case "kimi-coding": return "Kimi"
        case "qwen-oauth": return "Qwen"
        case "nous": return "Nous"
        case "anthropic": return "Anthropic"
        case "gemini": return "Google"
        case "xai": return "xAI / Grok"
        case "minimax-oauth": return "MiniMax OAuth"
        case "lmstudio": return "LM Studio"
        case "zai": return "Z.AI / GLM"
        case "custom": return "Custom"
        case "other": return "Other"
        default: return provider.capitalized
        }
    }

    /// SF Symbol icon name for a provider slug.
    static func icon(for provider: String) -> String {
        switch provider.lowercased() {
        case "ollama", "ollama-local", "lmstudio": return "desktopcomputer"
        case "ollama-cloud", "openrouter", "nous": return "cloud"
        case "anthropic", "openai", "openai-api", "gemini", "xai": return "sparkles"
        case "github-copilot", "copilot", "codex-oauth", "openai-codex", "qwen-oauth", "minimax-oauth": return "person.badge.key"
        case "lmstudio": return "desktopcomputer"
        case "zai": return "sparkles"
        default: return "server.rack"
        }
    }
}
