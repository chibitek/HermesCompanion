# Kanban task and desktop round-trip verification

## Verified behavior

The isolated gateway runner now executes native Hermes dashboard operations
alongside two independent iOS API clients. The native operations use the same
board databases and handlers as Hermes Desktop; they do not use Companion write
routes. The gateway and all records live in a disposable home.

The live iOS check creates a board and task, repeats creation with the same
idempotency key, and confirms the second client reads the same task. iOS completes
the parent before native Hermes creates and completes a dependent child. Native
operations then change the task's title/body and add a dashboard-authored comment
and a real text attachment. The phone verifies the child result and full summary,
comment attribution, workspace revision advancement and exact downloaded bytes,
including a non-ASCII character and newline.

A later phone priority edit preserves the desktop body. Native reads confirm the
phone's priority, completion status and result. Native operations delete the
attachment and child. The phone verifies the refreshed hierarchy and attachment
list, another workspace invalidation, and an actionable rejection when trying to
download the removed attachment. iOS archives the task and board; the independent
client confirms the archived task and removal of the board from the active list.

## Attachment and dependency editing in build 184

Bridge 0.1.11 and iOS 1.8.87 add attachment upload/delete controls and dependency
link/unlink controls. The expanded live check transfers the full native 25 MiB
limit in bounded chunks, repeats completion with the same operation ID, downloads
and compares every byte, checks an actionable size mismatch, then removes the
attachment. It creates and removes a dependency and verifies cycle rejection.
Existing native desktop operations still independently verify phone edits.

Upload retries preserve an operation ID across client recreation and selecting
the same file again. Server-side offset/checksum validation rejects conflicting
retries. Native attachment markers recover a committed upload if staging metadata
is lost, while native deletion events prevent old retries from resurrecting a
removed attachment. Partial staging expires lazily after seven days. File reading
runs off the UI thread and the composer does not participate in this workflow.
Metadata, transport and byte-count errors now include specific recovery guidance.
See [bridge protocol](../GatewayPlugin/README.md) for limits and ownership rules.

## Evidence

All thirteen real iOS gateway checks passed with zero failures or skips. The new
Kanban check took 2.06 seconds in that local run. Final reads contained zero chat
sessions, scheduled jobs, saved projects or active project selection. Saved cron
output was verified and linked project files retained their original contents.
The owned Kanban board was archived, preserving its records inside the disposable
home, which the runner removed after shutting down. The report independently
requires native observation of phone edits and native attachment/child removal.

The initial test sequence tried to complete a child with an unfinished parent.
Hermes correctly rejected it. The passing sequence respects that dependency rule;
no workflow policy was changed to make the test pass.

The first expanded attachment/dependency live run passed all thirteen checks.
A later run exposed issue #57: delayed auxiliary accounting recreated a deleted
conversation with zero messages. The deterministic native regression reproduces
that defect for title, vision and background-review responses. Compatibility
patch 8 now serializes accounting with deletion; 184 targeted native tests pass.
The bridge passes 32 tests and the app passes 179 ordinary simulator tests.
Final live verification after patch 8 passed all thirteen tests, with zero retained
sessions, jobs or projects. Native phone-edit and removal assertions passed, the
owned board was archived, and linked project files retained their contents. The
expanded Kanban check took 2.15 seconds. Build 184 delivery is tracked separately.

## Remaining feature coverage

| Native capability | Companion state |
| --- | --- |
| Create, edit, complete and archive tasks; comments | Implemented, now covered by the native round trip |
| Read hierarchy, child results and run summaries | Implemented; child result and full summary verified |
| Download task attachments and observe remote removal | Implemented; exact bytes and stale-download rejection verified |
| Upload and delete task attachments from iOS | Implemented; full-size transfer, replay and deletion verified |
| Add and remove task dependency links from iOS | Implemented; native cycle validation and unlink verified |
| Advanced task runtime, model, workflow and notification configuration | Not fully exposed or verified |
| Physical rendered refresh, accessibility and network transitions | Still require acceptance checks |

Physical file-picker presentation, assistive technology, interrupted mobile networking
and background/foreground transitions still require device acceptance.
