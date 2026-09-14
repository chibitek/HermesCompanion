# Hermes Companion sync repair verification

Current delivery: **1.8.79 (176)** with bridge **0.1.10** and all five gateway
compatibility patches. The phone and running gateway versions were rechecked on
September 14. TestFlight is Testing for the internal group; the App Store candidate
is Prepare for Submission. See [RELEASE_READINESS.md](RELEASE_READINESS.md).

The September 13 build 169 / bridge 0.1.9 snapshot below is historical. Its
deployment checklist has since been completed for the verified local gateway;
full parity and physical-device acceptance remain separate requirements.
This is a repair and verification record, not a full-parity or bug-free claim.

## Fixes prepared

| Finding | Change | Why it matters |
| --- | --- | --- |
| Incoming SSE frames were accumulated incorrectly through the line reader | Decode byte delimiters explicitly, retaining empty frame boundaries, Unicode, CRLF, and EOF handling | Deliver accepted/working/text/error events while the connection is open |
| Malformed frames and incomplete turns could be silently lost or treated as completed | Reject malformed frames, require completion, retain partial text, stop queue drain on failures | Avoid false success and accidental follow-up work after a failed turn |
| Active conversations refreshed mainly after foreground return | Serial foreground sync, recent-message probes, periodic full reconciliation, and bridge change notifications | Pick up persisted changes from other Hermes clients without reopening the chat |
| An older history request could overwrite a newer completed turn | Check connection, selection, turn, and request identity before applying history | Keep current messages and runtime state during concurrent operations |
| Reconnection replaced the client and erased the active chat | Reuse URLSession transport and retain current state while retrying reads | Recover without losing the selected conversation |
| History was truncated after 500 messages | Paginate oldest-first and reject repeated pages | Preserve older messages |
| Native session pages append pinned rows outside the requested page window | Follow `has_more`, `offset`, and `limit` rather than advancing by returned row count | Avoid skipping conversations when pins are backfilled |
| New-chat model choices were not sent when creating the session | Include the selected model/provider lock in the creation request; persist implicit new-chat selection | Match the displayed selection and restore chats created by the first send |
| HTTP status handling discarded server reasons | Preserve endpoint, status, structured reason/code, and retry guidance; redact the connection key and Bearer credentials | Make model, profile, rate-limit, permission, and compatibility errors actionable |
| Skills/toolsets and file/voice failures were hidden or generic | Display operation-specific reasons and retry guidance | Distinguish a failed read from an empty catalog |
| The composer sent images through both attachment inputs | Deduplicate legacy image data against selected image attachments | Avoid sending each photo twice |
| Binary documents were encoded as image data URLs | Reject unsupported content with filename/type and keep the composer draft | Prevent invalid requests and attachment loss during preflight |
| Every streamed token scheduled another delayed watchdog callback | Keep a monotonic deadline, with separate initial grace and activity timeout | Bound timer overhead during fast streams |
| Opening the main chat created a blank server session | Create on explicit New Session or first send | Avoid extra sessions and interference with restored history |

The composer distinguishes general gateway reachability from chat-stream activity.
A healthy `/health` response is not presented as proof that the model has answered.

## Change feed contract

`GET /api/companion/changes` uses the existing root gateway authorization decision.
There are no named-profile aliases, additional credential stores, or arbitrary
file paths accepted from a client. The feed samples server-owned state/project
SQLite files and WALs, profile configuration, job state, and Kanban databases and
metadata once per second. It emits an opaque revision when those files change,
plus five-second keepalives. Native domain reads remain authoritative.

This synchronizes persisted state. It does not mirror a draft being typed in a
separate desktop process or relay that process's unpersisted token stream.
Older history pages stay manually refreshed while being read. Discovery of new
repository folders outside these state files still uses the existing workspace
view refresh. Gateways without bridge 0.1.7 use periodic sync and show that mode.

## Historical build 169 verification summary

The build 169 simulator regression suite completed with 124 tests passed, two
opt-in live tests skipped, and zero failures. Native HTTP contract and bridge
regressions cover session leases, replay/fanout, interrupted runs, project writes,
and Kanban writes. Portable patches apply to the inspected upstream revision.

A real-provider integration attempt timed out. Complete two-way live conversation
success and complete desktop feature parity are not claimed. Physical-device
voice, background recovery, and CarPlay still need dedicated verification.

## Historical build 169 deployment checklist and coverage limits

- Deploy the four reviewed native patches and Companion bridge 0.1.9 using the
  gateway operator's normal approval and maintenance process.
- Verify skills discovery, custom-provider identity matching, profile routing,
  and a successful two-client conversation against the deployed server.
- Advanced Kanban operations, additional document workflows, and unpersisted
  desktop drafts/token streams remain outside the verified feature coverage.
- Durable run controls require server capability support; persisted history can
  continue to reconcile on older gateways through periodic reads.

Private conversations, device identifiers, server addresses, local filesystem
paths, signing details, and release-account records are intentionally excluded
from this public verification summary.
