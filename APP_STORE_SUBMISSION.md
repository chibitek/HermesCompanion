# App Store submission: Hermes AI Companion

## Current candidate

The newer **1.8.81 (178)** build adds confirmed session deletion to the queue and
structured-message repairs. Device inventory and launch confirm installation.
Build 178 is Testing in the internal TestFlight group.
The existing internal tester remains Invited
after the September 14 resend. TestFlight acceptance and installation are unverified.
Build 178 has not replaced the review candidate below.

- Version: **1.8.79 (176)**.
- Bundle identifier: `com.chibitek.hermescompanion`.
- TestFlight: build is **Testing** in the internal testing group; the account
  holder is **Invited**. Invitation acceptance and installation through
  TestFlight remain separate device actions.
- App Store Connect: this build replaces 1.8.64 (161). The saved candidate is
  **Waiting for Review**, with manual release selected.
- Apple confirmed **1 Item Submitted** on September 14, 2026. The submission
  contains **1.8.79 (176)**. Reviewer gateway access has not been supplied;
  review notes disclose the self-hosted gateway requirement. Arranging isolated
  access and refreshing/verifying screenshots remain follow-up work.
- No subscriptions are implemented in this candidate. The planned paid
  experiences are specified in
  [SUBSCRIPTION_RELEASE_PLAN.md](docs/SUBSCRIPTION_RELEASE_PLAN.md).

These are observed release states, not permanent guarantees. Recheck App Store
Connect before announcing a later release. Keep tester contact details, Apple
account identifiers, review credentials, and private server URLs out of Git.

## Promotional text

Stream chat from your own Hermes gateway, follow tool activity, manage saved
servers, and use voice when you choose.

## Description

Hermes AI Companion connects your iPhone to a Hermes Agent gateway that you run
on a Mac, Linux machine, or server.

### Chat with your agent

Stream replies, follow tool activity, browse conversations, and send photos or
files. View server health and connection guidance, reconnect after switching
apps, and queue follow-up instructions while a reply is running.

### Your workspace on your phone

Access supported gateway features, including sessions, models, skills, and
Kanban boards. Live workspace updates require a compatible Hermes Companion
bridge; older servers may use periodic synchronization. Available features
depend on your gateway version and configuration.

### Voice when you want it

Use dictation or open voice conversation explicitly. Choose playback voices and
speed. Typed chat does not require microphone access.

### Multiple servers and themes

Save, test, switch, and delete gateway connections. Customize the interface with
six visual themes.

### Direct connection

The app connects to the gateway you configure. Your gateway may use local models
or external AI providers, depending on your settings. Network protection depends
on your connection: use HTTPS or a trusted private network such as Tailscale.

### Requirements

A reachable Hermes Agent gateway with its API enabled and valid connection
credentials. iOS 26 or later. Tailscale is supported for private remote access.

Hermes AI Companion is open source under the MIT license. Source code, setup
guidance, and support are available on GitHub.

## Review preparation

- Explain that the app has no app account, but chat and workspace features
  require gateway authentication. A missing app sign-in does not mean reviewers
  can test chat without a configured gateway.
- Supply working, isolated reviewer access through App Store Connect only.
  Never share a personal gateway key or production conversations. Verify access
  from outside the developer's private network before submitting.
- Describe the ATS exception accurately: HTTP is protected by a VPN only when
  the user actually configured one. The app does not establish Tailscale itself.
- The app implements no custom cryptography and uses operating-system HTTPS/TLS.
- Do not advertise subscriptions, Watch, CarPlay, or native Vision Pro in this
  candidate. Those capabilities need their own implementation and verification.
- Inspect uploaded screenshots for accurate current behavior and absence of
  private information. The historical device-size checklist is not proof of
  current Apple screenshot requirements.
- The current `PRIVACY.md` describes optional Tailscale, external model providers,
  on-device recognition, and local diagnostic logs. App Store Connect currently
  declares Data Not Collected by the developer. Local logs and independently
  configured user gateways are distinct from automatic developer collection;
  re-evaluate the disclosure if a hosted service or collecting SDK is introduced.
  See [Apple's disclosure definitions](https://developer.apple.com/app-store/app-privacy-details/).
  The App Store privacy-policy URL must serve this updated policy.

## Candidate validation

The ordinary suite passed 142 tests and skipped four opt-in integration tests.
A separate repeated live-gateway run passed all four integration tests. The
first live run had a response timeout; variable local-model latency remains
tracked in [issue 55](https://github.com/chibitek/HermesCompanion/issues/55).
Physical music, microphone, and Bluetooth acceptance checks remain tracked in
[issue 53](https://github.com/chibitek/HermesCompanion/issues/53).

The signed build was uploaded to Apple and installed directly on the development
phone. That direct installation is not evidence of a TestFlight installation.
