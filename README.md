# Hermes Companion

Native iOS client for [Hermes Agent](https://github.com/NousResearch/hermes-agent) — chat with your AI agent, watch tool execution in real time, approve commands, and manage sessions from your phone.

## Features

- **Streaming chat** — responses appear token-by-token via SSE
- **Tool progress** — see what the agent is doing in real time (web search, file reads, terminal, etc.)
- **Command approval** — when the agent wants to run a dangerous command, approve or deny from your phone
- **Session management** — create, switch, fork, and delete conversation sessions
- **Skills & capabilities** — view what your Hermes instance can do
- **Provider-agnostic** — connects to any Hermes gateway API server, no hardcoded endpoints
- **Secure** — API key stored in iOS Keychain, all traffic encrypted via Tailscale

## Setup

### 1. Enable the Hermes API Server

On your Hermes machine, enable the API server platform and set an API key:

```bash
# In your Hermes .env file
API_SERVER_KEY=your-secret-key-here

# Enable the api_server platform in config
hermes gateway setup
```

The API server runs on port `8642` by default.

### 2. Set Up Tailscale (Recommended)

Tailscale creates a private, encrypted mesh network between your devices. No port forwarding, no exposed services, works through any NAT.

**On your Hermes machine:**
```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Authenticate
tailscale up

# Note your Tailscale IP
tailscale ip -4
# → 100.x.x.x
```

**On your iPhone:**
1. Install Tailscale from the App Store
2. Sign in with the same account
3. Connect

**Alternative connectivity options:**
- **Local network:** Use the machine's LAN IP (e.g., `http://192.168.1.50:8642`)
- **Cloudflare Tunnel:** `cloudflared tunnel` for a public HTTPS URL
- **WireGuard:** Manual VPN configuration

### 3. Install Hermes Companion

1. Open this project in Xcode
2. Build and run on your iPhone (or use TestFlight for distribution)
3. On first launch, enter:
   - **URL:** `http://100.x.x.x:8642` (your Hermes Tailscale IP + port)
   - **API Key:** The `API_SERVER_KEY` you set in step 1
4. Tap **Test Connection** to verify
5. Tap **Save & Connect**

## Architecture

```
┌─────────────────────┐         ┌──────────────────────┐
│  iPhone App          │  HTTP   │  Hermes Machine      │
│                      │  SSE    │                      │
│  ┌─────────────────┐ │◄───────►│  ┌────────────────┐ │
│  │ Chat (streaming)│ │         │  │ Hermes Gateway │ │
│  │ Tool progress   │ │         │  │ API Server     │ │
│  │ Approval flow   │ │         │  │ Port 8642      │ │
│  │ Sessions        │ │         │  │                │ │
│  │ Skills          │ │         │  │ Tools, memory, │ │
│  │ Settings        │ │         │  │ skills, cron   │ │
│  └─────────────────┘ │         │  └────────────────┘ │
└─────────────────────┘         └──────────────────────┘
         │                               │
         │      Tailscale mesh VPN       │
         │      (WireGuard, encrypted)   │
         └───────────────────────────────┘
```

The app talks directly to the Hermes gateway API server. No intermediate servers, no cloud relay, no telemetry. All processing happens on your Hermes machine.

## API Endpoints Used

| Endpoint | Purpose |
|----------|---------|
| `GET /health` | Connection test |
| `GET /v1/capabilities` | Feature discovery |
| `GET /api/sessions` | List sessions |
| `POST /api/sessions` | Create session |
| `GET /api/sessions/{id}/messages` | Load message history |
| `DELETE /api/sessions/{id}` | Delete session |
| `POST /api/sessions/{id}/chat/stream` | Streaming chat (SSE) |
| `GET /v1/skills` | List installed skills |
| `POST /v1/runs` | Start async run |
| `GET /v1/runs/{id}/events` | Stream run events (SSE) |
| `POST /v1/runs/{id}/approval` | Approve/deny commands |
| `POST /v1/runs/{id}/stop` | Stop a running agent |

## Roadmap

### Phase 1 (Current)
- [x] Connection setup with Tailscale
- [x] Streaming chat with SSE
- [x] Tool progress display
- [x] Command approval flow
- [x] Session management
- [x] Skills & capabilities viewer
- [ ] Camera/photo input for vision analysis
- [ ] Voice input (iOS Speech framework)
- [ ] Voice output (TTS)
- [ ] Push notifications for long-running tasks

### Phase 2
- [ ] Local LLM inference (MLX / llama.cpp on-device)
- [ ] Offline basic chat without server
- [ ] Widget for quick queries
- [ ] Shortcuts integration
- [ ] Multi-instance support (connect to multiple Hermes servers)

## Requirements

- iOS 26.0+ (Liquid Glass framework)
- Xcode 26.0+
- A running Hermes Agent instance with the API server platform enabled
- Tailscale (recommended) or network access to the Hermes machine

## Design

Hermes Companion uses Apple's **Liquid Glass** visual framework, introduced in iOS 26 and designed for iOS 27. All UI elements use `.glassEffect()` for translucent, light-refracting surfaces with real depth. The design language:

- **Translucent surfaces** — frosted glass panels for messages, tool chips, input bar, cards
- **Depth and layering** — glass tints convey state (teal for user, neutral for assistant, amber for approvals, red for danger)
- **Fluid animations** — `.smooth` spring curves, blinking cursors, pulsing thinking indicators
- **System-native** — feels like a first-party Apple app, not a wrapper

The app icon features a stylized Hermes winged motif in teal on a dark gradient, designed to look at home on the iOS 26 home screen with its rounded icon treatment.

## Building from Source

```bash
# Clone
git clone https://github.com/chibitek/HermesCompanion.git
cd HermesCompanion

# Generate Xcode project (requires xcodegen)
brew install xcodegen
xcodegen generate

# Open in Xcode
open HermesCompanion.xcodeproj
```

Select your iPhone or simulator, then build and run.

## License

MIT — see [LICENSE](LICENSE)

## Acknowledgments

- [Hermes Agent](https://github.com/NousResearch/hermes-agent) by Nous Research
- [Tailscale](https://tailscale.com) for seamless, secure networking
- [xcodegen](https://github.com/yonaskolb/XcodeGen) for project generation