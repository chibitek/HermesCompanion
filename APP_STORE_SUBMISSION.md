# App Store submission: Hermes AI Companion

## Current candidate

**1.8.86 (183)** adds complete scheduled-job delivery diagnostics and joins the
workspace watcher when foreground sync stops. Execution completion is separate
from delivery failure, queued receipts and unverified targets. Expandable reasons
remain readable and copyable; recovery clears stale warnings. Earlier connection,
steering, stream, deletion, reasoning and audio repairs remain included.

- Device: matching app/widget versions and a signed export verified. Inventory
  confirms 1.8.86 (183) installed. The locked phone blocked launch, so physical
  visual/audio acceptance remains incomplete.
- TestFlight: **Testing** in the existing internal group, containing builds
  176 through 183. The tester remains Invited; acceptance and TestFlight
  installation are unverified. The screenshot's Incompatible entry remains
  unidentified.
- App Review: build 182 was withdrawn and replaced. Apple confirmed one submitted
  item, **1.8.86 (183)**, on September 14, 2026 at **3:56 AM Eastern**.
  It is **Waiting for Review**, with manual release preserved.
- Validation: **177 ordinary simulator tests** and **twelve separate real-gateway
  checks** passed against final source. No jobs, sessions, projects or active
  selection remained; linked files were unchanged and saved scheduler output was
  verified. The native gateway previously passed 167 focused tests.
- Issues #65, #66 and #67 are resolved in the public branch. Physical audio (#53),
  variable model latency (#55), retained-session investigation (#57), external
  messaging delivery, full native job configuration and complete feature parity
  remain unfinished. Review notes disclose these limits.
- Reviewer gateway access and screenshot refresh remain incomplete.
- No subscriptions are implemented. Planned paid experiences are specified in
  [SUBSCRIPTION_RELEASE_PLAN.md](docs/SUBSCRIPTION_RELEASE_PLAN.md).

These are observed release states. Recheck App Store Connect before announcing a
later release. Keep tester contacts, Apple account identifiers, review credentials,
private captures and private server URLs out of Git.

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

The ordinary suite passed 159 tests and skipped six opt-in integration tests.
All six real disposable-gateway checks passed separately with zero retained
sessions. An earlier cleanup observation remains tracked in issue #57;
variable local-model latency remains
tracked in [issue 55](https://github.com/chibitek/HermesCompanion/issues/55).
Physical music, microphone, and Bluetooth acceptance checks remain tracked in
[issue 53](https://github.com/chibitek/HermesCompanion/issues/53).

The signed build was uploaded to Apple and installed directly on the development
phone. That direct installation is not evidence of a TestFlight installation.
