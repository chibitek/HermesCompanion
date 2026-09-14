# Connection and saved-server review

Current verified phone build: **1.8.87 (184)**. TestFlight shows Testing and the
replacement Apple review candidate is Waiting for Review, submitted September 14
at 4:43 AM Eastern with manual release. The tester invitation remains unaccepted.
The verified local server runs bridge **0.1.11** with eight compatibility patches.
See [RELEASE_READINESS.md](RELEASE_READINESS.md) for current evidence and remaining
acceptance work. The sections below retain the per-build repair history.

Initial connection repair: build 1.8.73 (170).

## Correctness review

The setup screen imposed 10/15-second deadlines around requests whose own deadlines were 5/20 seconds. A capability request could therefore lose its endpoint context and appear as a generic connection timeout. The setup screen now uses the individual request deadlines. Network failures identify the method, endpoint, network code, and recovery action, excluding headers, hostnames, and query values. Existing long-running chat deadlines are retained.

A successful unauthenticated health check could show green while authenticated session sync failed. Connection replacement now resets verified connection state; sync does not run during connection setup; session-list failures also set the sync status. The status view distinguishes health response from a connected gateway and reports sync failures. An empty session list no longer produces a chat-sync timestamp.

## Coherence review

Saved-server removal existed in Settings but was absent from the connection test screen, including its failure recovery flow. Delete Server is now available below the test controls for a selected saved server. It calls the existing removal operation, identifies the target in a confirmation, disconnects an active connection, and preserves remote sessions. The edit screen's Done button now dismisses the screen.

## Verification

The iOS simulator suite passed: 128 tests executed, two live-gateway tests skipped, zero failures. Coverage includes a nonresponding health request, capability timeout context, exclusion of private URL details, health success with session-sync failure, and an empty session catalog without a chat-sync claim. The app and extension compiled.

## Deployment and live checks

Build 1.8.73 (170) was installed and launched on the paired iPhone. Apple processed the uploaded build successfully; TestFlight shows Ready to Submit, with testing notes saved. External beta distribution has not been submitted.

The four native gateway patches were deployed after 266 canonical tests passed. Bridge 0.1.9 passed 28 tests and was installed. A legacy backup directory inside the plugin search path was overriding the current plugin; moving that backup outside plugin discovery allowed the current bridge to load. Keep plugin backups outside all discovery directories.

Live requests confirmed skills, projects, Bots, boards, and bridge 0.1.9 capabilities. A real chat verification created a temporary session, observed a live workspace change event, received the expected model response, and read the user message and assistant reply through an independent client. The temporary session was deleted successfully. Model completion took 92.58 seconds, so this proves delivery and persistence, not acceptable response speed.

The physical phone still requires verification after credential replacement. The simulator's two live-gateway tests remain skipped; the separate live HTTP check does not establish every iOS/desktop feature or concurrent model-stream behavior. Full feature parity and model latency remain open acceptance work.

## Bridge warning recovery, build 1.8.74 (171)

An initial HTTP 404 from the live workspace feed permanently ended its watcher,
leaving an install warning visible even after the server bridge was upgraded.
The watcher now retries missing endpoints every 30 seconds while the app remains
foregrounded, retaining periodic sync meanwhile. A successful reconnect clears
the warning and resumes workspace invalidations. The warning identifies the
endpoint and response and explains automatic retry rather than asserting that
a specific bridge version is absent.

The regression check exercises a 404 followed by a live SSE response using the
same client and foreground sync task. It verifies the warning clears and a
workspace change is processed without reconnecting or restarting the app.

## Selected-server recovery review

Correctness review found that automatic and manual connection completions could write state after a disconnect or server switch. Automatic fallback also selected unrelated saved servers after a timeout or authentication failure. The repair keeps retries on the chosen server and checks client identity after each asynchronous boundary, so a delayed response cannot restore an obsolete connection.

The lifecycle review found duplicate startup connection entry points in the app and splash view. A second successful connection replaced the API client and cleared chat state. Startup uses the splash preference once, while foreground sync revalidates a failed selected connection without replacing its client or transcript. Regression coverage exercises delayed responses, disconnects, and recovery after a temporary transport failure. These findings do not yet establish full feature parity or physical-device recovery across every network transition.

Seven focused recovery regressions passed: selected-server recovery after timeout, rejected credentials despite healthy `/health`, session-catalog recovery, delayed automatic/manual responses after disconnect, superseded connection attempts, and duplicate startup preserving the active conversation. The broader simulator run passed 132 tests with zero failures and two opt-in live tests skipped; the two latest authentication/catalog regressions passed separately.

Both opt-in integration tests then passed against the patched native gateway, bridge 0.1.9, and the installed local model in a temporary tool-free Hermes home. The strengthened conversation test starts the real foreground sync loop and requires a second client's rename and reply to appear automatically within ten seconds, without calling `syncNow` from the test. Independent run viewers and event replay also matched. All diagnostic sessions were removed and the temporary gateway exited. This verifies the real iOS client/server contract on the simulator, not physical-device Wi-Fi transitions, voice, or full feature parity.

The connection changes are packaged in 1.8.75 build 172. Worktree and full published-branch history secret scans found no leaks before publication. Personal/device identifiers, pairing material, and environment files are excluded from public changes.

Build 172 was archived, its exported application signature verified, and installed on the physical phone. Device inventory confirmed 1.8.75 (172), launch succeeded, and the application log recorded a successful automatic connection. Apple accepted the upload; TestFlight tester assignment and distribution remain unverified. The native gateway was not restarted for this client update.

## Board management coverage

Issue #51 records the missing iOS board creation, metadata editing, active-board
selection, and archive controls. Bridge 0.1.10 exposes the corresponding native
Hermes handlers under existing root authorization. The app checks the new
`board_manage` capability and validates board identity in every write receipt.
Native slugs, project/workdir validation, and default-board archive refusal are
preserved. The archive route always retains files; it cannot request hard delete.

The review found that native board creation writes metadata on a reused slug.
The bridge returns an existing board unchanged on a repeated ID, and the editor
keeps the same payload after an uncertain creation result. Updates omit unchanged
fields to preserve unrelated desktop edits. This is not a cross-process atomic
create-or-compare transaction; simultaneous first creation of the same new slug
still depends on the native domain's concurrency behavior.

Thirty bridge tests passed using native per-board SQLite storage in a disposable
home. They include phone-to-native and native-to-phone metadata changes, retry
preservation, active selection, archive retaining task rows, invalid board IDs,
default-board refusal, and authorization before writes. The fixture previously
forced every board to one database path; removing that override was necessary to
verify actual board isolation and archive retention.

The full simulator run passed 137 tests with three opt-in live tests skipped.
All three live integration tests then passed against the installed native gateway
and local model in an isolated Hermes/Kanban home, including two-client board
changes, live invalidation, conversation sync, and run-event replay.

Build 1.8.76 (173) was archived, signature-verified, installed and launched on the
physical phone. Apple accepted its upload. TestFlight processing, tester assignment,
and availability remain unverified. The phone log recorded a successful automatic
connection after the deployed gateway resumed service.

The first graceful restart exposed a native macOS API startup failure: binding
the recently closed API port failed, and the gateway classified that as a fatal
configuration conflict while its other platforms continued. After confirming the
port was bindable, a second drain-aware restart restored the API. Authenticated
checks returned bridge 0.1.10, board management enabled, and the live board catalog.
Automatic recovery from this transient startup bind failure remains follow-up work.

## API restart bind recovery plan

Issue #52 traces the macOS restart outage to a native API bind failure that the
gateway treats as permanently fatal. The repair will reuse the gateway reconnect
queue for two additional exclusive bind attempts after the initial failure,
without blocking other platforms or changing socket reuse settings. A conflict
that persists through that bounded window must remain fatal and actionable.
Tests will drive native startup aggregation and reconnect using real TCP sockets
and isolated Hermes storage, checking recovery, persistent ownership, and cleanup.

The repair is packaged as compatibility patch 5. Its first regression failed on
the original code; 227 distinct canonical tests passed with the fix. An additional
full native gateway verification kept an authenticated Companion event feed open
across SIGUSR1 shutdown, relaunched once, and recovered the API and live feed
automatically in 33.30 seconds. The macOS test using a real server-closed HTTP
connection also recovered after the native socket wait. Persistent conflicts
remained fatal after the bounded attempts and retained their original listener.

Deployment used one drain-aware restart. The replacement process confirmed native
revision `afbd3e296e` and a connected API platform. Subsequent live requests
verified health, bridge 0.1.10 capabilities, and an authenticated workspace event.
No production tasks or conversations were created for these checks. Build 173
remains the installed/uploaded iOS build; this repair changes only the server.

## Composer controls, build 174

The requested composer change removes the red stop square from the primary
action. While a response streams, the primary control uses a turning guidance
arrow; when idle it always uses an up arrow. An empty tap focuses text entry.
The existing trailing response cursor remains the busy indicator. Stop moves
to the control's context menu; the idle context menu retains voice conversation.

The current session-chat transport queues follow-ups after the response ends.
This change preserves that behavior and labels it "Queue guidance" for
accessibility; it does not claim the separate durable-run steering endpoint
controls session-chat turns. Attachment guidance is refused explicitly while
retaining the draft, since the existing follow-up queue accepts text only.

All four composer action regressions passed. The release archive and exported
application signature verified successfully. Build 1.8.77 (174) was installed
on the paired phone; iOS refused automatic launch because the device was locked.
This UI change does not add live session-chat
steering; it preserves the existing queued-follow-up transport.

Device inventory confirmed 1.8.77 (174). Apple accepted the uploaded build;
TestFlight processing and tester availability remain unverified.


## Text chat audio ownership, build 175

Issue #53 covers audio changing during typed chat. Idle phone and CarPlay voice
controllers both observed system interruptions and unconditionally selected the
playback category during cleanup. A regression reproduced ambient changing to
playback without starting either controller. They now ignore interruptions when
they do not own audio and deactivate only sessions they activated. Dictation
cleanup also avoids selecting a new playback category.

Text focus, draft editing, sending, and queuing suspend the optional wake
listener. This suspension survives automatic foreground and sheet transitions,
dictation completion, and pending permission callbacks. Only explicitly opening
voice conversation or re-enabling Hey Hermes clears it. Wake capture is released
before dictation starts or a voice page opens, avoiding a later SwiftUI callback
deactivating the new recorder. Settings explain the resulting behavior.

Voice preview now uses the system-managed speech audio session and stops on
leaving settings, so preview completion does not retain shared playback.
The idle-interruption regression failed before the fix. The focused voice,
dictation, and composer suite passed all 30 tests after the initial fix.
Physical playback continuity and microphone indicators require observation on the
updated phone; Simulator category checks do not prove Bluetooth route behavior.

The final full iOS suite reported 139 passing tests, three integration checks
skipped, and zero failures. The signed release archive and exported application
signature verified. Paired-device inventory confirmed 1.8.78 (175) installed.
Public tracked files and history passed secret scanning; no signing files, env
files, private device identifiers, or local logs are included in the change.


## Stream text fidelity, build 176

Issue #54 records the live spacing failure visible in the phone screenshot.
The renderer treated each delta as a whole document: it trimmed whitespace,
discarded JSON objects without a text field, unwrapped objects with a content
field, and stripped literal markup. This corrupted prose and code before the
completed response arrived and could remove a complete JSON answer entirely.

Assistant deltas, completed answers, and recovered partial text now preserve
the gateway's content. Reasoning stays separate through event metadata, which
the native API already supplies. A run-completed event leaves any uncommitted
text available for the send pipeline to save. Regression tests pass SSE frames
through the actual AppStore event handler and check every live prefix, spaces,
newlines, indentation, JSON, literal markup, and reasoning separation.

All three new regression cases failed on the prior renderer. The focused
stream, SSE parser, and markdown/voice suite passed after the repair. The real
gateway integration also observes live prefixes and compares the completed
answer with canonical history; it runs in a disposable Hermes home against the
installed local model, without changing the production gateway or conversations.

The first live run passed stream fidelity, two-client conversation/rename, and
board live invalidation, but independent run replay timed out after 123 seconds.
Stream fidelity took 73 seconds and conversation/rename took 12 seconds. Ollama
logged a large prompt prefill and failed requests in that window; the cause is
not yet established. Issue #55 tracks this separate performance failure. These
results do not establish fast or reliable responses for every workload.

The repeated full live suite passed all four checks: independent run viewers
and replay in 8.2 seconds, stream fidelity in 4.8 seconds, two-client chat and
rename in 6.2 seconds, and board invalidation in 1.1 seconds. The verifier removed
all diagnostic sessions, stopped its owned gateway, and removed the temporary
home. This warm repeat does not resolve the initial latency failure in #55.

The full iOS suite passed 142 tests, with the four opt-in integration tests
skipped there and exercised separately above. The release archive and exported
signature verified. Device inventory confirmed 1.8.79 (176), and launch succeeded.
