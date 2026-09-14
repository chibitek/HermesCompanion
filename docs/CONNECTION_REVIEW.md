# Connection and saved-server review

Build 1.8.73 (170).

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
