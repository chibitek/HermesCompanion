# Connection and saved-server review

Build 1.8.73 (170).

## Correctness review

The setup screen imposed 10/15-second deadlines around requests whose own deadlines were 5/20 seconds. A capability request could therefore lose its endpoint context and appear as a generic connection timeout. The setup screen now uses the individual request deadlines. Network failures identify the method, endpoint, network code, and recovery action, excluding headers, hostnames, and query values. Existing long-running chat deadlines are retained.

A successful unauthenticated health check could show green while authenticated session sync failed. Connection replacement now resets verified connection state; sync does not run during connection setup; session-list failures also set the sync status. The status view distinguishes health response from a connected gateway and reports sync failures. An empty session list no longer produces a chat-sync timestamp.

## Coherence review

Saved-server removal existed in Settings but was absent from the connection test screen, including its failure recovery flow. Delete Server is now available below the test controls for a selected saved server. It calls the existing removal operation, identifies the target in a confirmation, disconnects an active connection, and preserves remote sessions. The edit screen's Done button now dismisses the screen.

## Verification

The iOS simulator suite passed: 128 tests executed, two live-gateway tests skipped, zero failures. Coverage includes a nonresponding health request, capability timeout context, exclusion of private URL details, health success with session-sync failure, and an empty session catalog without a chat-sync claim. The app and extension compiled.

Physical-device connectivity after credential replacement still requires re-pairing and verification. The skipped live tests do not establish provider completion or full two-way feature parity. Native bridge deployment and live provider verification remain separate acceptance work.
