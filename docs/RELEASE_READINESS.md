# Development Release Readiness

## Current delivery: 1.8.87 (184)

Task attachments now support full-size uploads, resumable retries and deletion.
Task dependencies can be added and removed with native ownership and cycle
checks. Download errors distinguish metadata, byte-count and transport failures.
The final full simulator suite passed 179 ordinary tests; all thirteen opt-in
real gateway checks passed separately. The bridge passed 32 tests.

Issue #57 was reproduced deterministically: delayed auxiliary usage could recreate
a deleted conversation before saving its generated title. Patch 8 now checks
existence and writes usage in one transaction. All 184 targeted native tests pass;
the final live run retained no sessions, jobs or projects. Linked files were
preserved and the test board was archived. See [KANBAN_LIVE_VERIFICATION.md](KANBAN_LIVE_VERIFICATION.md).

The verified local gateway was gracefully restarted after confirming no active
runs or delegations. It runs native revision `480383eb3f` with eight compatibility
patches and bridge 0.1.11. Live reads confirmed healthy status, attachment/link
writes, the 25 MiB file limit and 4 MiB chunks. Installed bridge files match the
verified sources. Build 184 was archived, exported with matching app/widget
versions and verified signing, and installed on the paired device. Device
inventory confirms 1.8.87 (184). Launch was blocked by the locked phone.
Apple accepted the upload at 4:37 AM Eastern on September 14. TestFlight shows
Testing in the existing internal group with one tester and nine builds. The
tester remains Invited. Build 183 was withdrawn, and Apple confirmed one submitted
item, 1.8.87 (184), at 4:43 AM Eastern, Waiting for Review. Manual release remains
selected. Review notes disclose missing reviewer gateway access, unchanged
screenshots and unfinished physical audio/network/visual acceptance. Full feature
parity and paid platform experiences remain unfinished.

## Historical delivery diagnostics update: 1.8.86 (183)

Scheduled jobs now separate execution status from delivery failures, queued
receipts and unverified delivery. Expandable rows retain the complete reason,
and successful recovery clears stale delivery warnings. See
[JOB_DELIVERY_DIAGNOSTICS.md](JOB_DELIVERY_DIAGNOSTICS.md).

Investigation #66 found a request-body helper that stopped on temporary stream
unavailability and a workspace watcher that could outlive its sync owner. A real
bound-stream regression failed before the helper repair. Live sync now cancels
and joins its watcher. The final full simulator suite passed 177 ordinary tests,
with twelve opt-in real-gateway checks skipped for their separate run. All twelve
then passed against the final source with zero retained jobs, sessions, projects
or active selection, unchanged linked files and verified saved scheduler output.

Build 183 has matching app/widget versions, a verified signed export and a
confirmed device installation. Launch was blocked by the locked phone. TestFlight
shows Testing in the existing internal group. Build 182 was withdrawn; Apple
confirmed one submitted item, 1.8.86 (183), on September 14 at 3:56 AM Eastern,
Waiting for Review with manual release preserved. The tester remains Invited.
Physical visual/audio acceptance, external messaging delivery, full native job
configuration, reviewer access and complete feature parity remain unfinished.

## Subsequent Kanban verification, same build 183

All thirteen real gateway checks passed, including native desktop task edits,
comments, child results, attachment bytes/removal and iOS completion/archive.
The native half independently verified the phone's saved fields. No chat, job or
project records remained; the owned Kanban board was archived in the disposable
home and linked files were retained. See [KANBAN_LIVE_VERIFICATION.md](KANBAN_LIVE_VERIFICATION.md)
for exact scope; the later build 184 section adds attachment/dependency editing. This work
does not change the shipped binary, native gateway or Apple review candidate.

## Historical scheduled-job sync update: 1.8.85 (182)

Remote scheduled-job changes now refresh the Companion list through workspace
invalidation, with a 30-second foreground polling fallback. Older responses
cannot overwrite newer job snapshots. A failed read displays a job-specific
stale-data warning and retry action without erasing unrelated platform errors.
See [JOB_SYNC.md](JOB_SYNC.md).

Validation: 174 ordinary simulator tests passed in the final full rerun; all ten
real-gateway checks passed separately. No jobs, sessions, projects or active
project remained, and linked files retained their contents. The job regression
failed before repair and passed afterward. Intermittent admission-test issue #66
was still open at that delivery. Native job capability/execution issue #65 was
resolved by the subsequent server verification below.

Build 182 has matching app/widget versions and a verified signed export. Device
inventory confirms installation; launch was blocked by the locked phone, so
physical visual/audio acceptance remains incomplete. Apple processed the upload
and build 182 is Testing in the existing internal group. The build 181 submission
was withdrawn. Apple confirmed one submitted item, 1.8.85 (182), on September 14
at 3:16 AM Eastern, Waiting for Review with manual release selected. Invitation
acceptance, reviewer gateway access, screenshots, physical network transitions
and full feature parity remain incomplete.

## Subsequent server-only job contract verification

Patch 7 advertises actual cron availability and the eight native job routes.
The focused native suite passed 167 tests. All eleven real iOS checks passed,
including actual local-model scheduled execution, saved local output and live
result synchronization. Cleanup left no jobs, sessions, projects or active
selection; linked files were unchanged. The local server was gracefully restarted
on `faecddc545`; health, job capabilities and bridge 0.1.10 were verified live.
The iOS binary and Apple candidate remain build 182. External channel delivery
and full native job configuration remain outside this verified subset.

## Historical run monitoring update: 1.8.84 (181)

Build 181 preserves live output, the replay cursor and status monitoring when
reattaching the run already selected. The regression failed before repair and
now reaches the canonical terminal result without losing or duplicating text.
See [RUN_MONITOR_REATTACH.md](RUN_MONITOR_REATTACH.md).

The full suite passed 171 ordinary iOS tests, with eight opt-in checks skipped.
All eight real-gateway checks then passed separately with zero retained sessions
or metadata. No gateway change was required; the six compatibility patches and
bridge 0.1.10 from build 180 remain the deployed server baseline.

A subsequent verification-only update added a real two-client project lifecycle
check. All nine live checks passed with zero remaining sessions, projects or
active selection; linked server files retained their exact contents. No app
binary changed. [FEATURE_COVERAGE.md](FEATURE_COVERAGE.md) records current
evidence and remaining feature work, including scheduled-job capability coherence.

The archive has matching app/widget versions and the signed export was verified.
Physical-device inventory confirms 1.8.84 (181) installed, but launch was blocked
by the locked phone. Physical visual/audio acceptance remains incomplete. Apple
processed the upload and build 181 is Testing in the existing internal group.
TestFlight invitation acceptance and install are verified.

The older build 180 submission was withdrawn. Apple confirmed one submitted item,
**1.8.84 (181)**, on September 14 at 2:44 AM Eastern; it is Waiting for Review with
manual release selected. Reviewer access, screenshot verification, full feature
coverage, physical audio (#53), model latency (#55) and retained-session
investigation (#57) remain open. No subscription is included. The following
snapshots are historical.

## Historical reasoning update: 1.8.83 (180)

Build 180 makes reasoning controls operational for capable gateways without
changing another client's saved conversation options. Conversation default,
Server default and Off are distinct; the UI shows the last response's applied
configuration and explains unavailable controls on older gateways. See
[CHAT_REASONING.md](CHAT_REASONING.md).

Validation passed 170 ordinary iOS tests and 165 native gateway tests. All eight
isolated real-gateway checks passed separately, including a second independent
client verifying reasoning defaults, with zero retained sessions or metadata.
The running Hermes 0.21.2 gateway reports revision
`266a90387d144836aa1ce4633362f1db4c0b7d61`, containing all six compatibility
patches. Bridge 0.1.10 is unchanged. A graceful restart completed after checking
for active work; health, advertised capability and actual reasoning behavior were
verified, and the owned production verification session was deleted.

The archive has matching app/widget versions and the signed export passed
verification. Physical-device inventory confirms 1.8.83 (180) installed. Launch
and visual acceptance of this build remain unverified. Apple processed the
upload; build 180 is Testing in the existing internal group. The tester remains
accepted by September 14, so acceptance and installation through TestFlight are verified.
The screenshot's Incompatible entry is still unidentified.

The pending build 179 submission was withdrawn. After a transient submission
error, Apple confirmed one submitted item, **1.8.83 (180)**, on September 14 at
2:29 AM Eastern. It is Waiting for Review with manual release selected. Reviewer
gateway access, screenshot refresh, physical audio acceptance (#53), variable
model latency (#55), and the intermittent retained-session observation (#57)
remain open. No subscription or additional paid platform experience is included.
The records below are historical.

## Historical active steering update: 1.8.82 (179)

Build 179 adds native active-chat steering and recoverable undelivered guidance
from other clients. The full suite passed 168 ordinary tests; all seven isolated
real-gateway checks passed with zero retained sessions or metadata. See
[CHAT_STEERING.md](CHAT_STEERING.md).

The signed archive and exported app/widget versions match. Physical-device
inventory confirms 1.8.82 (179) installed; launch was blocked because the phone
was locked. Apple accepted the upload; build 179 is Testing in the existing
internal group. The tester remains accepted by September 14 with no registered device; TestFlight
acceptance and installation are verified. The screenshot's Incompatible
entry is still unidentified.

The pending build 178 submission was withdrawn. Apple confirmed one submitted
item, **1.8.82 (179)**, on September 14 at 1:58 AM Eastern; it is Waiting for Review
with manual release selected. Reviewer gateway access and screenshot refresh
remain follow-up work. No subscription or additional paid platform experience
is included. The build 178 record below is historical.

## Build 178 September 14 delivery snapshot

Companion **1.8.81 (178)** is installed on the physical phone; device inventory
confirms its version and launching the app succeeded. The first installation
command lost its connection; the later inventory check established completion.
The app and widget have matching versions, and the signed export was verified.
Build 178 is Testing in the internal TestFlight group.
Build 178 adds confirmed session deletion and specific in-app update notes to the
queue, structured-message, typed-chat audio and text-fidelity repairs.

The internal group contains builds 176, 177 and 178. The existing tester remains
accepted by September 14; the invitation was resent on September 14 after the tester reported the
app absent from the active list. TestFlight acceptance and installation remain
unverified, and the screenshot's Incompatible entry is still unidentified.
The connected phone meets the exported build's requirements.

The previous build 176 review submission was withdrawn. Apple confirmed
**1.8.81 (178)** submitted on September 14; it is Waiting for Review with manual
release selected. TestFlight availability and App Review are separate states.

The running Hermes **0.21.2** gateway reports code revision
`afbd3e296ef825922bdd8d79b7d6f4f933288d36`, containing all five compatibility
patches. Installed bridge **0.1.10** files match the current public source.
Authenticated native and bridge capabilities returned HTTP 200 on September 14.
No restart was needed to reapply code already running.

The latest source suite passed **159 tests**, with six live checks skipped.
All six checks then passed against the real gateway and local model in an
isolated workspace. A first six-test run failed its final cleanup gate despite
passing the tests; after adding per-test cleanup assertions, the repeat passed
with zero sessions remaining. The intermittent observation remains in #57.
Model latency remains open in #55, and physical music/microphone/Bluetooth
acceptance remains open in #53.

The privacy policy now describes optional Tailscale, configured model providers,
on-device speech recognition, and local diagnostic logs. The submitted review
notes disclose the gateway requirement; working isolated reviewer access and
screenshot refresh/verification remain follow-up work.
No subscription, Watch, native Vision Pro, or unapproved CarPlay experience is
included in this candidate's advertised scope.

See [CONNECTION_REVIEW.md](CONNECTION_REVIEW.md) and
[APP_STORE_SUBMISSION.md](../APP_STORE_SUBMISSION.md). Historical build and
deployment snapshots below describe earlier checks, not current installed state.

## Session deletion repair in build 178

Session deletion now requires the native receipt type, requested conversation ID
and `deleted: true` before clearing local conversation or queued drafts. Failed
confirmation preserves local state with a specific diagnostic. The full suite
passed 159 ordinary tests with six skipped, and all six real-gateway checks passed
separately with zero retained sessions. The repair is installed in build 178,
and is included in the submitted build 178. Earlier builds 176 and 177 omit it. See [SESSION_DELETION_RECEIPTS.md](SESSION_DELETION_RECEIPTS.md).

## Queue and stream repair in build 177

Queued follow-ups now retain server and conversation ownership through navigation,
restart, and uncertain sends. A visible recovery list permits review and removal;
dispatch waits for confirmation and never skips an earlier item requiring review.
The source simulator suite passed 151 tests, with five live checks skipped; all
five checks passed separately against an isolated real gateway and local model.
The structured-message repair subsequently passed 158 ordinary tests and six
live checks. Both repairs are included in the phone-installed build 177,
and are also included in the submitted build 178.
See [QUEUE_RELIABILITY.md](QUEUE_RELIABILITY.md) and
[SSE_MESSAGE_CONTRACT.md](SSE_MESSAGE_CONTRACT.md) for scope and verification.

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


## Physical launch update

The paired iPhone is unlocked and Hermes 1.8.87 (184) launches via devicectl.
TestFlight invite acceptance remains the only gap to the app appearing in iOS TestFlight.


## TestFlight acceptance recorded

App Store Connect shows Installed 1.8.87 (184) for erick.grau@chibitek.com on the
paired iPhone. Physical launch is verified via devicectl.
