# Queued follow-up reliability

Issue: [#56](https://github.com/chibitek/HermesCompanion/issues/56).

## Finding

Before this repair, queued chat guidance could be silently lost when a conversation changed or a deferred send lost ownership.

What: `selectSession` calls `stopStreaming`, which deletes every queued message for the connection. Queue entries have no session identity. The drain removes and persists its head before a deferred task verifies the current client, turn and session. A failed queued request has no recoverable entry or visible queue UI.

How: Trace the composer through `queueMessage`, `sendMessage`, `selectSession`, `stopStreaming` and the per-connection UserDefaults restoration. Correctness review found destructive navigation and a remove-before-guard race. A persistence/UI review found the stored queue cannot identify its original conversation and is not shown to the user.

Why: Accepted follow-up text can disappear or later run in the wrong conversation. Retrying an uncertain chat request automatically could duplicate server work.

## Repair

Implemented behavior:
- Persist stable queue identities and conversation ownership; bind input queued during first-session creation only to that creation turn.
- Preserve queues on navigation; explicit stop/deletion affects only the intended conversation.
- Keep an in-flight entry until confirmed success and require review after uncertainty or restoration.
- Show saved follow-ups with conversation context and explicit recovery/removal controls.
- Verify navigation, persistence, legacy restoration, dispatch failure and ownership races with behavioral regressions.

The queue is scoped by server and records stable message IDs, original session
IDs, and delivery state. Guidance entered during session creation binds only to
that creation turn. Restored, interrupted, or failed items require review;
dispatch never skips past an earlier item requiring attention. Corrupt stored
data is retained and cannot be overwritten by another server's queue.

The Follow-ups sheet shows the original conversation and delivery state. Moving
an item to the composer is explicit, requires an empty draft, and does not send
it. In-flight items cannot be recovered or removed through that sheet. Explicit
Stop and conversation deletion discard only the intended conversation's queue;
navigation, archival, and remote removal preserve text for review. An unscoped
legacy queue migrates once as unassigned drafts, never as automatically sendable
guidance for every saved server.

## Verification and release boundary

The original navigation regression failed twice before the repair. The ordinary
simulator suite now reports **151 passed, 5 opt-in live checks skipped, and no
failures**. Behavioral regressions exercise navigation, explicit stop, server
ownership, restart and in-flight restoration, legacy migration, corrupt storage,
recovery restrictions, first-session creation, failed dispatch, and ordered
delivery. A coherence pass checked queue ownership from persistence through the
composer and confirmed no credential storage or gateway protocol changes.

All **five live-gateway checks passed** against the patched native gateway and
installed local model in an isolated workspace. The queue check confirmed two
ordered user messages and two assistant responses, with no duplicate follow-up
in canonical history; it completed in 14.6 seconds. Stream fidelity, two-client
sync, run replay, and board invalidation also passed. Verification left zero
sessions, then removed its temporary gateway and workspace. This is not a claim
that model latency is fixed for every workload; issue #55 remains open.

This repair is packaged in **1.8.80 (177)**, installed on the physical phone
and accepted for upload by Apple. Launch verification awaits an unlocked phone;
TestFlight processing and distribution are being checked. The Apple review
candidate remains **1.8.79 (176)**, Waiting for Review with manual release.
