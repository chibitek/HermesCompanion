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

This adds verification to the existing build 183 behavior. It does not require a
new app binary or server deployment. The prior 177 ordinary simulator tests
remain the implementation baseline; the live suite now contains thirteen checks.

## Remaining feature coverage

| Native capability | Companion state |
| --- | --- |
| Create, edit, complete and archive tasks; comments | Implemented, now covered by the native round trip |
| Read hierarchy, child results and run summaries | Implemented; child result and full summary verified |
| Download task attachments and observe remote removal | Implemented; exact bytes and stale-download rejection verified |
| Upload and delete task attachments from iOS | Missing |
| Add and remove task dependency links from iOS | Missing; links are currently read-only |
| Advanced task runtime, model, workflow and notification configuration | Not fully exposed or verified |
| Physical rendered refresh, accessibility and network transitions | Still require acceptance checks |

Attachment metadata mismatch, byte-count mismatch and transport failures also
need specific user-facing diagnostics in the download path. Those paths currently
retain generic errors despite other endpoint-specific error improvements.
