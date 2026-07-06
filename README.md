# Hermes Companion

Native iOS client for [Hermes Agent](https://github.com/NousResearch/hermes-agent) by Nous Research. Chat with your AI agent, watch tool execution in real time, approve commands, and manage sessions from your phone.

Built by [Chibitek Labs](https://chibitek.com).

## Screenshots

### Chat
Real-time streaming chat with tool execution visibility, session management, and multimodal support.

<img src="screenshots/chat.png" width="300" alt="Chat screen showing a daily briefing conversation with streaming response" />

### Settings
Configure your Hermes server connection, manage capabilities, voice, and appearance. Version display with links to docs and GitHub.

<img src="screenshots/settings.png" width="300" alt="Settings screen showing server config, skills, voice, and version info" />

### Provider Selector
Switch between model providers (Nous, OpenRouter, Ollama, Huggingface, and more). Providers and models sync from your connected Hermes server.

<img src="screenshots/provider-selector.png" width="300" alt="Provider selector showing available AI providers" />

### Model Selector
Pick from any model available on your Hermes gateway. Models refresh automatically when you change providers.

<img src="screenshots/model-selector.png" width="300" alt="Model selector showing available AI models" />

### Appearance and Themes
Six built-in themes including Liquid Glass (default), Matrix terminal, Retro Amber CRT, Neon, Blue Hacker, and Cyberpunk.

<img src="screenshots/appearance-themes.png" width="300" alt="Appearance settings showing theme picker with Cyberpunk selected" />

## Features

### Chat
- Real-time streaming chat (SSE) with full tool execution visibility
- Real-time tool event chips showing what the agent is doing
- Approval prompts for tool execution
- Multimodal support (send photos and files)
- Session history with rename and fork support
- Auto-login on launch via Keychain
- Foreground sync for replies sent from other Hermes surfaces (macOS, Telegram, Discord)
- Auto-scroll to most recent message on session open

### Voice
- Voice-to-text dictation via SFSpeechRecognizer
- Full 2-way voice conversation mode (tap waveform icon)
- On-device LLM via Apple Foundation Models (iOS 26+)
- TTS playback via AVSpeechSynthesizer
- Dedicated cyberpunk voice page with CRT effects, scanlines, glitch text
- Center-orb audio visualizer with glow
- Screen stays awake during voice conversations
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
- Voice configuration (speed, pitch, voice selection)
- Premium voice service integration (Amazon Polly, Google Cloud TTS)

### Input Bar
- Claude-style model picker pill
- Plus button for photo/file attachments
- Mic button (voice-to-text)
- Waveform button (2-way voice conversation)
- Enter key sends message

## Design Handoff
This project includes comprehensive design handoff documents for creating a unified look and feel:
- [DESIGN_HANDOFF.md](design/DESIGN_HANDOFF.md) - High-level design requirements and goals
- [TECHNICAL_SPEC_FOR_DESIGN.md](design/TECHNICAL_SPEC_FOR_DESIGN.md) - Detailed technical specifications for designers
- [HANDOFF_TO_ENGINEERING.md](design/HANDOFF_TO_ENGINEERING.md) - Engineering implementation guide

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
  DEVELOPMENT_TEAM=YOUR_TEAM_ID CODE_SIGN_IDENTITY="Apple Development" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -allowProvisioningUpdates build
```

## License

MIT
