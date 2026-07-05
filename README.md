# Hermes Companion

Native iOS client for [Hermes Agent](https://github.com/NousResearch/hermes-agent) by Nous Research. Chat with your AI agent, watch tool execution in real time, approve commands, and manage sessions from your phone.

Built by Chibitek Labs.

## Features

### Chat
- Real-time streaming chat (SSE) with full tool execution visibility
- Real-time tool event chips showing what the agent is doing
- Approval prompts for tool execution
- Multimodal support (send photos and files)
- Session history with rename support
- Auto-login on launch via Keychain
- Foreground sync for replies sent from other Hermes surfaces (macOS, Telegram, Discord)

### Voice
- Voice-to-text dictation via SFSpeechRecognizer
- Full 2-way voice conversation mode (tap waveform icon)
- On-device LLM via Apple Foundation Models (iOS 26+)
- TTS playback via AVSpeechSynthesizer
- Dedicated cyberpunk voice page with CRT effects, scanlines, glitch text
- 4 voice page presets: Matrix, Retro Amber, Neon, Blue Hacker

### Themes
- Hermes (default Liquid Glass)
- Matrix (green terminal, scanlines, CRT glow)
- Retro Amber (CRT amber phosphor, scanlines)
- Neon (magenta/cyan neon, scanlines)
- Blue Hacker (ICE blue terminal, scanlines)
- Cyberpunk (dark glass with neon accents)

All terminal themes use monospaced fonts, sharp corners, dense spacing, CRT scanlines, and phosphor glow effects.

### Settings
- Model/provider selector (loads from /v1/models)
- Skills browser with search
- Connection management with auto-reconnect
- Appearance settings (theme, font size, color scheme)

### Input Bar
- Claude-style model picker pill
- Plus button for photo/file attachments
- Mic button (voice-to-text)
- Waveform button (2-way voice conversation)
- Enter key sends message

## Technical

- iOS 26.0+ target
- SwiftUI with Liquid Glass APIs
- Provider-agnostic (connects to any Hermes gateway)
- Keychain credential storage
- Background/foreground reconnection
- Audio session interruption handling
- Accessibility labels and reduce-motion support

## Build

```bash
xcodegen generate
xcrun xcodebuild -project HermesCompanion.xcodeproj -scheme HermesCompanion \
  -configuration Debug -sdk iphoneos \
  DEVELOPMENT_TEAM=DF9FB764AR CODE_SIGN_IDENTITY="Apple Development" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -allowProvisioningUpdates build
```

## License

MIT
