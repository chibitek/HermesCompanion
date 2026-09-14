# App Store submission: Hermes AI Companion

## Current candidate

**1.8.85 (182)** fixes scheduled jobs remaining stale after remote writes.
Workspace changes and periodic synchronization refresh the list; older responses
cannot overwrite newer snapshots, and failures show a specific warning and retry
action. Earlier run-monitoring, reasoning, steering, deletion, queue, stream and
audio repairs remain included.

- Version: **1.8.85 (182)**.
- Bundle identifier: `com.chibitek.hermescompanion`.
- Device: matching app/widget versions and signed export verified. Inventory
  confirms installation; launch was blocked by the locked phone. Physical
  visual/audio acceptance remains incomplete.
- TestFlight: **Testing** in the existing internal group alongside builds 176
  through 181. Invitation acceptance and TestFlight installation remain
  unverified. The screenshot's Incompatible entry is still unidentified.
- App Review: the pending build 181 submission was withdrawn. Apple confirmed
  **1 Item Submitted** on September 14, 2026 at 3:16 AM Eastern, containing
  **1.8.85 (182)**. It is **Waiting for Review**, with manual release selected.
- Validation: the final full rerun passed 174 ordinary iOS tests. All ten separate
  real-gateway checks passed with zero retained jobs, sessions, projects or active
  project; linked files were retained. The job regression failed before repair
  and passed afterward. The gateway remains unchanged.
- Scheduler execution/delivery and capability coherence (#65), intermittent
  admission-test investigation (#66), physical audio (#53), variable model
  latency (#55), retained-session investigation (#57) and full feature parity
  remain incomplete. Review notes disclose these verification limits.
- Reviewer gateway access has not been supplied. Isolated reviewer access and
  screenshot refresh/verification remain follow-up work.
- No subscriptions are implemented. Planned paid experiences are specified in
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

The ordinary suite passed 159 tests and skipped six opt-in integration tests.
All six real disposable-gateway checks passed separately with zero retained
sessions. An earlier cleanup observation remains tracked in issue #57;
variable local-model latency remains
tracked in [issue 55](https://github.com/chibitek/HermesCompanion/issues/55).
Physical music, microphone, and Bluetooth acceptance checks remain tracked in
[issue 53](https://github.com/chibitek/HermesCompanion/issues/53).

The signed build was uploaded to Apple and installed directly on the development
phone. That direct installation is not evidence of a TestFlight installation.
