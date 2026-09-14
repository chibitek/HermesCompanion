# Development Release Readiness

## Current September 13 delivery state

Companion 1.8.75 build 172 is installed on the physical phone, and its log
recorded a successful automatic connection after launch. Apple accepted its
upload, but tester assignment and TestFlight availability are not yet verified.
The installed gateway includes all four patches in `GatewayPatches`, and the
live bridge advertises 0.1.9. Authenticated session reads and the change feed
were verified over loopback and the server's Tailscale interface. This does not
prove every phone network transition or every Hermes feature works.

Selected-server recovery fixes were verified for build 172 and tracked in issue #50. See
[CONNECTION_REVIEW.md](CONNECTION_REVIEW.md) for the failure cases, repair, and
verification record. Historical build and deployment snapshots below are
retained as evidence of earlier checks, not current installed state.

## Text-Only Audio Isolation Follow-Up

The typed-message background keep-alive no longer generates or plays a silent
audio loop. Its start/end/foreground paths do not touch AVAudioSession, and
the obsolete phone/CarPlay handoff hooks were removed. Background execution
now uses only the iOS time-limited task; indefinite text streaming while
suspended is not promised. Foreground reconnection remains in place.

All 9 VoiceActivationLogicTests passed in
`Test-HermesCompanion-2026.09.11_23-38-31--0400.xcresult`, including a real
AVAudioSession category-preservation test around the text lifecycle. This is
not a physical-device music continuity or long-background recovery test.

Wake listening now defaults off. Shared defaults perform a one-time reset of
the previous automatic setting before views read it; later explicit opt-ins
are preserved. The legacy defaults migration no longer restores the old value.
Backgrounding pauses wake listening instead of unconditionally activating a
recording audio session. Idle listener cleanup does not deactivate an audio
session it never acquired; voice handoff transfers ownership.

All 8 VoiceActivationLogicTests passed on the dedicated iOS 26.5 simulator in
`Test-HermesCompanion-2026.09.11_23-34-43--0400.xcresult`, including fresh-install,
upgrade-consent, and idle audio cleanup regressions. Music continuity on a
physical iPhone remains unverified; this change has not been installed there.

As of September 11, 2026. This is a verification record, not a release approval
or a claim that the full product goal is complete.

## Historical September 12 Verification Snapshot

Source `390c86f` plus the local-only voice cleanup passed 93 iOS Simulator tests
on September 12. Bridge 0.1.6 passed all 16 tests again. The release also
removed the dormant ElevenLabs streaming path, its key storage, an unused
mutable variable, and a duplicate provider-icon pattern. Successful arm64
compilation does not establish signing, physical-device behavior, or feature
completeness. Earlier evidence below is historical; this snapshot supersedes
its build/test counts, not its unresolved release requirements.

## Historical Installed Versus Unreleased

The latest verified phone installation is 1.8.63 build 158, from merged PR 46.
It contains the September 12 local-only voice cleanup. The local Hermes gateway
was restarted with the Companion bridge 0.1.6; its health endpoint returned 200
and the Companion projects route returned 401 without credentials, confirming
route registration. The phone launch was confirmed by a device screenshot.
Physical voice, music continuity, workspace navigation, and complete parity
have not yet been verified on the device.

The prior verified phone installation was 1.8.62 build 156, from merged PR 42.

## Evidence

- Build 158 contains the September 12 local-only voice cleanup. It passed all 93
  iOS tests on iPhone 17 Pro Simulator, iOS 26.5, and all 16 bridge tests. It
  removes the hidden ElevenLabs streaming path, provider/key storage, an unused
  mutable variable, and a duplicate provider-icon pattern. The signed Release
  build was installed on the physical phone.

- 69 iOS unit tests passed on iPhone 17 Pro Simulator, iOS 26.5. Coverage includes
  stale list/history/creation responses, deleted session state, canonical Bot
  ownership, task hierarchy, schedule omission, and the CarPlay callback selector.
- Ten bridge route/domain contract tests passed. No live data was mutated by
  these tests.
- The generic iOS Release build passed with signing disabled. Remaining compiler
  warnings include asynchronous notification API suggestions. This does not
  verify signing, phone installation, or Swift 6 mode.
- Subsequent bubble-layout work removes that deprecated screen-size lookup.
  Hosting-controller checks cover long user/assistant text at 240- and 700-point
  container widths, verifying bounded width and vertical reflow. These are layout
  measurements, not physical-device screenshots or a complete visual review.
- Direct real-domain reads verified six task details and project history in four
  profiles containing project sessions. This does not establish HTTP deployment
  of the new routes or visual verification of the new iOS screens.
- The two local gateway compatibility patches previously passed 162 focused
  server tests. A live local Qwen turn confirmed its named provider and model;
  the diagnostic session was removed. See `../GatewayPatches/README.md`.

## Required Before Release

- Public branch updates, server patch deployment, Apple upload, and phone installation were authorized. The feature PR remains a draft; merging is not complete.
- Increment the build number and perform a signed device build/install. An
  unsigned Release compilation does not verify signing or installation.
- Verify the new project and Kanban screens on the phone, including long text,
  small fonts, themes, navigation, and refreshing after changes made on the Mac.
- Exercise microphone startup, interruption, stop/restart, speech playback,
  background/foreground recovery, and physical CarPlay disconnect behavior.
- Verify API reachability after a graceful gateway restart. A transient macOS
  port-bind failure was observed; a running service alone is insufficient proof.
- Review credential ownership and configuration before enabling cross-profile
  serving. The live non-default native session routes currently return 404.
- Revalidate hosted/other Hermes endpoints separately; local success is not
  evidence of compatibility with every host.

## Product Gaps

Cross-profile Bot message submission, project mutations, Kanban editing, and full
artifact browsing/download workflows remain unfinished. Project history is
limited by Hermes's hydrated-tree membership and native filtering. Physical
voice stability and complete desktop feature parity have not been established.
Do not describe this development branch as bug-free or fully synchronized across
every Hermes feature based on the focused tests above.

## Attachment Development Update

Bridge 0.1.4 and the native task screen now implement task-owned attachment
downloads and Quick Look previews. Eleven bridge tests pass, including an
authorized HTTP byte download and denied/foreign-attachment requests. Client
tests cover filename containment and attachment ownership; redirects are refused
and downloaded byte count must match metadata. This is not deployed or verified
on the phone yet, and it is not a general artifact browser for all Hermes output.

## Voice Playback Development Update

Voice replies now preserve the server's text instead of dropping lines about
latency or response time. Playback uses iOS speech synthesis only. System speech
callbacks must match the current utterance, and delayed microphone resumption
is invalidated when playback stops or is replaced.

The September 11 22:30 simulator test log records 77 passing tests, including
late start/finish/cancel callbacks and active cancellation. Xcode also reported
a thread-priority inversion during the speech-stop test. This warning is not
resolved by the passing assertions and needs performance validation on a phone.
Tests do not establish actual audio quality, uninterrupted microphone recovery,
or physical-device voice stability. These changes remain unreleased.

## Empty Project Folder Update

Bridge 0.1.5 preserves discovered zero-session repositories when the native
drill-in omits them. It uses only the same profile's current overview, requires
an exact project ID and an explicit zero session count, and never substitutes
a nonempty preview for hydrated history. Fourteen bridge tests pass. This does
not remove the native session-list limits and has not been deployed.

## Voice Request Ownership Update

The phone and CarPlay now rely on AppStore's activity-aware stream watchdog
instead of independent 20/60-second voice failure timers. The phone no longer
speaks an untracked two-word or first-sentence prefix: it speaks the complete
returned answer, so audible playback starts after generation completes. This
does not implement incremental speech queueing.

Remote voice turn identifiers reject completions from canceled, replaced, or
closed conversations. All 78 iOS tests passed in the September 11 22:42 run,
including ownership across cancellation/restart and existing stream-watchdog
tests. Slow real-device tool turns, audible completeness, and network loss still
require end-to-end phone validation before release.

## Model Selection Development Update

Settings catalog browsing no longer writes model/provider preferences; explicit
model selection remains the mutation. Provider changes request a refreshed
catalog, and catalog responses are checked against the current request,
connection, and picker provider. A session model missing from the catalog uses
the session's effective provider metadata, not the gateway's global provider.

Model-lock success/error callbacks are scoped to the connection, session
selection, and newest model-selection request. Regression tests cover reversed
responses and a success/failure arriving after switching sessions. These guards
protect the client display; they do not establish ordering of competing writes
from different devices on the server. Interactive picker and phone verification
remain required.

Active-session model/provider preferences now change only after a successful
server lock response. Rejected or pending locks preserve the confirmed runtime;
successful locks use the server's normalized model/provider identity. New-chat
selection remains a local preference until its session is created. All 82 iOS
tests passed in the September 11 22:51 run, including rejection and normalization
regressions. The earlier Release-build snapshot predates this follow-up.

## Duplicate Model Sources

The compact model picker now receives the full server catalog, retaining
different providers that report the same model ID. Source rows use a composite
model/provider identity, send the selected provider explicitly, and mark the
active source using both values. Duplicate rows for the same pair are collapsed.
Older gateways retain their existing metadata fallback without inferring an
inference provider from the model author's name. This is unreleased and still
requires interactive multi-provider verification on the phone.

## Project Count Development Update

Bridge 0.1.6 reads each profile's total session count through Hermes's read-only
session domain helper and supplies a positive upper bound to both native project
tree calls. This removes dependence on the 2,000/5,000-row default caps. Native
grouping/filtering remain authoritative; concurrent additions between the count
and tree reads are not covered by an atomic snapshot guarantee.

Sixteen bridge tests pass. A real read counted 10 profiles and 857 session rows
(largest profile: 833), so the former caps did not explain this host's reported
missing folders. Deployment and further sync verification remain necessary.

## Full Project Detail Audit

A subsequent real-domain audit attempted every one of the 437 overview entries
across all 10 profiles: 436 returned matching project details; one returned no
project. The missing entry is a discovered parent workspace with three sessions
in child working directories. Its native grouping/detail mismatch remains
unresolved; this is not proof of full folder parity.

The iOS detail view no longer substitutes its prior overview snapshot when the
server returns no project. It displays Project Unavailable instead of presenting
stale folder data as a successful refresh. Bridge 0.1.5 and later still preserve
genuinely empty discovered folders from the current server overview.

Follow-up native grouping verification located all three sessions from the
unavailable parent entry in two explicit, user-created projects (two sessions
in one, one in the other). Each returned through its existing hydrated detail.
The parent is an additional discovery-tier listing; no missing transcript was
demonstrated by this mismatch. Do not duplicate/reassign those sessions to the
parent just to make its displayed count match. The native parent overview/detail
inconsistency still needs an upstream-compatible resolution.

## Dictation Draft Update

Composer dictation now merges recognition results against a captured original
draft instead of replacing that draft and then appending the transcript again.
Confirm commits once, cancel restores the original draft, and automatic finish
keeps the final transcript. Recording stops when the composer disappears or the
scene backgrounds. Editing/submission are disabled while dictation is active to
avoid races with recognition callbacks. Starting a new recording clears the old
transcript before permission checks.

Pure merge tests cover successive partial results, empty text, and whitespace.
These do not prove on-device recognition, button interaction, or audio-session
recovery; that phone verification remains required.

The composer no longer requests microphone and speech permissions on appearance.
Dictation and voice conversation request them through their existing guarded
start paths when invoked. Voice-page appearance still starts conversation mode
automatically; this removes duplicate permission requests, not automatic listening
after an explicit voice-mode entry. First-use permission UI remains unverified
on a physical device.

## Complete Session Pagination

The iOS session client no longer fetches all pages and then discards rows after
the first 200. Gateways without a total count continue through full pages until
a short/empty page. Repeated pages, or an empty page before an advertised total
is reached, fail the refresh rather than report a partial list as complete.
All 88 iOS tests passed in the September 11 23:20 run, including 252-session
catalogs with/without totals and a repeating-page response. Concurrent changes
during server pagination still require end-to-end validation; this is not an
atomic-snapshot guarantee or proof of remote deletion reconciliation.

## Remote Deletion Reconciliation

After a session refresh, an idle active chat missing from the list is checked
through the native direct-session endpoint. A 404 clears the active chat,
runtime, messages, pending stream state, and saved pointer. Other failures leave
the chat intact. Connection, selection, and refresh identifiers guard delayed
lookup results and the subsequent restoration step. Both regular and platform
refreshes use the same reconciliation path.

Tests cover not-found, server error, a readable session omitted from the list,
and a late not-found response after switching chats. Live Mac deletion and phone
foreground recovery still require device verification. This assumes the connected
Hermes gateway implements the native direct-session endpoint; alternate hosted
endpoint behavior must be verified separately.
