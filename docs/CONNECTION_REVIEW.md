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
