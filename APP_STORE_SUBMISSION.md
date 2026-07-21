# App Store Submission — Hermes Companion

## App Info

| Field | Value |
|---|---|
| **Name** | Hermes Companion |
| **Subtitle** | Chat with your AI agent |
| **Bundle ID** | com.chibitek.hermescompanion |
| **SKU** | hermes-companion-ios |
| **Primary Category** | Productivity |
| **Secondary Category** | Developer Tools |
| **Price** | Free |
| **Copyright** | Chibitek LLC |

---

## Description

Hermes Companion connects your iPhone to your own AI agent — the one running on your machine, with your models, your tools, and your data. No cloud middleman. No subscriptions. Just you and your agent, end to end.

**YOUR AGENT, YOUR MACHINE**
You run the Hermes Agent gateway on your own hardware — a Mac, a Linux box, or a VPS. Hermes Companion connects to it over an encrypted Tailscale tunnel. Your conversations, your files, your voice — nothing passes through a third-party server.

**REAL-TIME CHAT**
Stream responses as they're generated. Watch your agent think, call tools, and reason in real time. Approve or deny tool executions before they run. Send photos and files directly in chat.

**HERMES TALK — VOICE MODE**
Tap the waveform and your phone becomes a full-screen voice terminal. Matrix digital rain, CRT scanlines, and a pulsing center-orb visualizer. On-device transcription via SFSpeechRecognizer — your voice never leaves the phone until you send it. TTS playback with configurable voice and speed.

**ANY MODEL, ANY PROVIDER**
Switch between any model your gateway can reach — Nous Portal (300+ models), OpenRouter, OpenAI, Anthropic, Google, local Ollama models, and any OpenAI-compatible endpoint. Star multiple favorites. Switch mid-conversation.

**MULTIPLE SERVERS**
Connect to as many Hermes gateways as you want. Personal agent at home, work agent at the office, dedicated coding agent on a GPU box. Switch with one tap. Each server keeps its own sessions, models, skills, and preferences.

**SIX THEMES**
Liquid Glass, Matrix terminal green, Retro Amber CRT, Neon, Blue Hacker, and Cyberpunk. Every theme transforms the entire app.

**PRIVACY FIRST**
- No cloud dependency — connects directly to your gateway
- Credentials in iOS Keychain, never in plaintext
- On-device voice transcription
- No analytics, no telemetry, no tracking
- Open source (MIT) — fully auditable

**REQUIREMENTS**
- A running Hermes Agent gateway (self-hosted)
- Tailscale on both your iPhone and your gateway machine
- iOS 26.0+

---

## Keywords

hermes,ai,chat,assistant,llm,voice,agent,self-hosted,open source,tailscale,terminal,matrix,cli,developer,tools,coding,privacy,local,offline

---

## Screenshots (required sizes)

| Size | Device | What to capture |
|---|---|---|
| 6.9" | iPhone 17 Pro Max | Chat with streaming response + tool events |
| 6.9" | iPhone 17 Pro Max | Hermes Talk voice mode with Matrix rain |
| 6.9" | iPhone 17 Pro Max | Model picker with favorites |
| 6.9" | iPhone 17 Pro Max | Settings / server picker |
| 6.7" | iPhone 15 Pro Max | Chat with streaming response |
| 6.7" | iPhone 15 Pro Max | Hermes Talk voice mode |
| 6.7" | iPhone 15 Pro Max | Model picker |
| 6.5" | iPhone 11 Pro Max | Chat |
| 6.5" | iPhone 11 Pro Max | Voice mode |
| 5.5" | iPhone 8 Plus | Chat |

---

## App Privacy Labels

### Data Types Collected

| Data Type | Collected? | Linked to Identity? | Used for Tracking? | Purpose |
|---|---|---|---|---|
| **Contact Info — Email Address** | No | — | — | — |
| **User Content — Photos/Videos** | Yes | No | No | App Functionality (camera attachments sent to user's own server) |
| **User Content — Audio Data** | Yes | No | No | App Functionality (voice transcription, on-device only) |
| **User Content — Customer Support** | No | — | — | — |
| **Identifiers — User ID** | No | — | — | — |
| **Diagnostics — Crash Data** | No | — | — | — |

### Privacy Details

- **Photos/Videos**: Photos taken with the in-app camera are sent to the user's self-hosted Hermes Agent gateway. They are not stored on any third-party server.
- **Audio Data**: Microphone audio is processed on-device by Apple's SFSpeechRecognizer for transcription. Raw audio is never stored or transmitted. The transcribed text is sent to the user's self-hosted gateway.

---

## App Review Notes

### ATS Exception (NSAllowsArbitraryLoads)

The app connects to user-configured Hermes Agent gateways over Tailscale WireGuard tunnels. These gateways run on private IPs in the 100.64.0.0/10 range (Tailscale CGNAT). Because the IP addresses are user-specific and dynamic, we cannot enumerate them in NSExceptionDomains. The app uses HTTPS where the gateway supports it, but many self-hosted setups use plain HTTP on local/Tailscale networks. All connections are encrypted at the network layer by Tailscale's WireGuard tunnel regardless of the HTTP scheme.

### Encryption (ITSAppUsesNonExemptEncryption = false)

The app uses only HTTPS/TLS for network communication. No custom cryptographic algorithms are implemented. The Tailscale WireGuard tunnel is provided by the Tailscale app, not by Hermes Companion.

### CarPlay

CarPlay support is implemented but requires the `com.apple.developer.carplay-audio` entitlement, which needs separate approval. The entitlement is not included in the current build. We will request it separately and submit an update.

### Self-Hosted Architecture

This app is a thin client for the open-source Hermes Agent platform (github.com/NousResearch/hermes-agent). It does not connect to any Chibitek-operated servers. All data processing happens on the user's own hardware. The app has no sign-up, no account creation, and no backend services of its own.

---

## Export Compliance

- **ITSAppUsesNonExemptEncryption**: No (set in Info.plist)
- **Encryption**: Only standard HTTPS/TLS. No custom cryptography.
- **ECCN**: 5D992 (mass market)
- **CCATS**: Not required

---

## Version Info

| Field | Value |
|---|---|
| **Version** | 1.8.40 |
| **Build** | 117 |
| **What's New** | ElevenLabs TTS support, voice provider picker, sessions pinned to bottom, voice latency improvements, CarPlay voice mode, App Store readiness |
