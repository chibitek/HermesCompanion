# Privacy Policy

**Last updated: September 14, 2026**

Hermes AI Companion is built by Chibitek. This policy describes the current
iPhone application and its connection to a gateway you configure.

## Your gateway and model providers

The app sends your chat messages, attached photos and files, and requested
workspace changes directly to your configured Hermes Agent gateway. It reads
conversation history and workspace data from that gateway. The app does not
require a Chibitek account or a Chibitek-operated relay.

Your gateway controls storage and processing of that content. It may run models
locally or forward content to external AI providers or tools according to its
configuration. A remotely hosted gateway is also operated under its host's
policies. Chibitek does not control those independent servers or providers.
Self-hosting does not by itself mean that every model request stays on your
hardware.

## Network connections

The app supports user-configured HTTP and HTTPS addresses. HTTPS protects the
connection using the operating system's TLS implementation. A private network
such as Tailscale can provide additional protection when you have configured it
on both ends. The app does not establish a Tailscale tunnel itself, and a plain
HTTP address is not automatically encrypted.

## Voice, photos, and files

- Dictation, voice conversation, and optional wake-phrase listening require
  microphone and speech permissions. The recognition paths require Apple's
  on-device speech recognition; when it is unavailable the app reports that
  voice recognition cannot start.
- Recognized text is sent to the gateway when you submit it or use voice
  conversation. The app's speech-recognition paths do not send raw microphone
  audio to the gateway.
- Speech playback uses Apple's system speech synthesizer. The current app has
  no ElevenLabs integration.
- Photos and files you choose to attach are sent to your configured gateway.
  Its model or tool configuration determines any further processing.
- Apple-managed features such as Siri and TestFlight operate under Apple's
  own privacy settings and policies.

## Information stored on your device

The app stores connection credentials in iOS Keychain. It also keeps local
settings, connection and conversation selections, and recovery information for
pending requests. Conversation history is read from the gateway.

Local diagnostic logs help investigate connection and voice problems. They can
include connection addresses, error details, transcribed text, and excerpts of
responses. The app does not automatically upload these logs to Chibitek.
Review and redact logs before sharing them with support, particularly in a
public GitHub issue.

Removing a saved server in the app removes that saved connection; it does not
delete conversations or files from the server. Use the server's own controls
to manage its retained data.

## Analytics and support

The app has no advertising, tracking, or third-party analytics SDK. It does
not automatically send app usage or diagnostic logs to Chibitek.

If you choose to contact support through GitHub, GitHub and the recipients can
access what you submit. Public issues are public. Do not include passwords,
API keys, private conversations, or personal files in an issue.

## Children

The app is not directed to children under 13. Chibitek does not knowingly
collect personal information from children through this app.

## Changes and contact

Updates to this policy are published on this page. For privacy questions, use
the [project's support page](https://github.com/chibitek/HermesCompanion/issues)
without including sensitive information in a public issue.
