# Development Release Readiness

As of September 11, 2026. This is a verification record, not a release approval
or a claim that the full product goal is complete.

## Latest Verification Snapshot

Source `d6ff737` passed 80 iOS Simulator tests and a fresh generic iPhone Release
build with signing disabled on September 11 at 22:49. Bridge 0.1.5 passed all
14 tests again. The physical Portatus XVII Pro Max was available and paired;
no installation or gateway restart was performed.

The Release build still reports dormant ElevenLabs captured-reference warnings,
an unused mutable Markdown variable, a duplicate provider icon switch pattern,
and asynchronous notification API suggestions. Successful arm64 compilation
does not establish signing, physical-device behavior, or feature completeness.
Earlier evidence below is historical; this snapshot supersedes its build/test
counts, not its unresolved release requirements.

## Installed Versus Unreleased

The last verified phone installation is 1.8.62 build 156, from merged PR 42.
It includes Projects, Bots, Kanban browsing, and canonical Bot history.

Development source through `1eee679` adds project-session history, full Kanban
task details and hierarchy, refreshed Bot details, and session/voice/job fixes.
Those changes have not been installed on the phone or pushed for review.
The development bridge is 0.1.3; updating only the iOS app does not deploy its
new gateway routes. No multi-profile serving configuration change was made.

## Evidence

- 69 iOS unit tests passed on iPhone 17 Pro Simulator, iOS 26.5. Coverage includes
  stale list/history/creation responses, deleted session state, canonical Bot
  ownership, task hierarchy, schedule omission, and the CarPlay callback selector.
- Ten bridge route/domain contract tests passed. No live data was mutated by
  these tests.
- The generic iOS Release build passed with signing disabled. Remaining compiler
  warnings include captured weak references in dormant ElevenLabs code, the
  deprecated screen-size lookup in `GlassBubble`, and a duplicate provider icon
  pattern. This does not verify signing, phone installation, or Swift 6 mode.
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
- Local branch inventory contains only `Dev_Erick` and `main`, with one worktree.

## Required Before Release

- Obtain approval to push/open the PR, merge, and install the updated bridge/app.
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
