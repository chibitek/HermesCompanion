# Privacy Policy

**Last updated: July 21, 2026**

Hermes AI Companion ("the App") is built by Chibitek LLC. This policy explains how your data is handled.

## Data Collection

**The App does not collect, store, or transmit your personal data to any third party.**

- **No accounts.** The App has no sign-up, no login, and no user accounts. There is no Chibitek-operated server.
- **No analytics.** The App contains no analytics, telemetry, crash reporting, or tracking of any kind.
- **No cloud storage.** Your conversations, settings, and preferences are stored locally on your device and on your self-hosted Hermes Agent gateway.

## How the App Works

The App connects directly to a Hermes Agent gateway that you run on your own hardware. All communication is between your iPhone and your gateway over an encrypted Tailscale WireGuard tunnel. No data passes through Chibitek or any third-party server.

## Data You Control

- **Gateway credentials** (URL and API key) are stored in the iOS Keychain — not in plaintext, not in UserDefaults, not synced to iCloud.
- **Voice transcription** runs on-device via Apple's SFSpeechRecognizer. Raw audio is never stored or transmitted. Only the transcribed text is sent to your gateway.
- **Photos and files** you attach in chat are sent directly to your self-hosted gateway. They are not stored by Chibitek.
- **Conversation history** lives on your Hermes Agent gateway. You control it entirely.

## Third-Party Services

The App integrates with services you configure:
- **ElevenLabs** (optional TTS): If you provide an ElevenLabs API key, text is sent to ElevenLabs for speech synthesis. Their privacy policy applies to that data.
- **Tailscale**: Network connectivity is provided by Tailscale's WireGuard tunnel. Their privacy policy applies to network traffic.

## Children's Privacy

The App is not directed to children under 13. We do not knowingly collect data from children.

## Changes

We may update this policy. Changes will be posted on this page.

## Contact

For privacy questions: open an issue at [github.com/chibitek/HermesCompanion/issues](https://github.com/chibitek/HermesCompanion/issues).
