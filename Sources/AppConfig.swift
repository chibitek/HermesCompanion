// HermesCompanion
// Native iOS client for Hermes Agent
// https://github.com/NousResearch/hermes-agent
//
// MIT License — see LICENSE
//
// This app is provider-agnostic. It connects to any running Hermes Agent
// gateway API server via a user-configured URL and API key.
// No hardcoded endpoints, branding, or credentials.

import Foundation

/// Global app configuration constants
enum AppConfig {
    /// App name shown in UI
    static let appName = "Hermes"
    /// GitHub repo for help/about
    static let repoURL = "https://github.com/chibitek/HermesCompanion"
    /// Hermes Agent docs
    static let hermesDocsURL = "https://hermes-agent.nousresearch.com/docs"
    /// Default API server port (Hermes gateway default)
    static let defaultPort = 8642
    /// Keychain service name
    static let keychainService = "com.chibitek.hermescompanion"
    /// SSE keepalive timeout (seconds)
    static let sseKeepaliveTimeout: TimeInterval = 30
    /// Max image size for camera attachments (points)
    static let maxImageDimension: CGFloat = 1024
    /// JPEG quality for camera images
    static let imageJPEGQuality: CGFloat = 0.8
}