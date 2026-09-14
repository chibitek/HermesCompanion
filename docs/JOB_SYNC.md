# Scheduled-job synchronization

## Finding and repair

Remote job writes reached the native server and emitted bridge workspace changes,
but Companion refreshed only conversations on those events. The platform screen
loaded jobs on entry and manual refresh, leaving its open list stale.

The real two-client regression reproduced this: native job creation succeeded,
then the app store failed to observe it within ten seconds. Nine other live
checks passed; cleanup left no jobs, sessions, projects or active project, and
linked files remained intact.

Job reads now participate in workspace invalidation and the foreground sync
loop, with a 30-second polling fallback. All reads share a request generation so
late platform or mutation refreshes cannot overwrite a newer snapshot. Server
changes invalidate outstanding reads and reset the polling cadence. Failed job
reads preserve cached rows but display a specific stale-data warning and retry
action; recovery clears that warning without erasing unrelated platform errors.

## Verification scope

The real isolated test uses two independent iOS clients for create, edit, pause,
resume, run admission and deletion. It asserts automatic app-store updates and
zero retained jobs. The isolated adapter has no scheduler ticker: run admission
is verified by its changed next-run time, not by executing or delivering a job.
Production scheduler execution and delivery remain separate acceptance work.

Focused regressions cover out-of-order snapshots, explicit failure and recovery,
and periodic reads without a live feed while avoiding rapid repeated polling.
The gateway's static jobs_admin flag is a separate contract inconsistency and
must not be treated as proof that mounted job write routes are unavailable.

The repaired real-gateway run passed all ten checks with zero failures or skips.
The job lifecycle check took 4.06 seconds. Final canonical reads found no jobs,
sessions, projects or active project; both linked project files were unchanged.
Native capability and scheduler execution follow-up is tracked in issue #65.

The final full simulator rerun passed 174 ordinary tests, with ten opt-in live
checks skipped (those passed separately). An earlier full run observed an
intermittent existing run-admission body assertion failure; a focused rerun and
twenty repetitions passed. Its cause remains unproven and tracked in issue #66.
The assertion now identifies each request field instead of reporting a generic
boolean failure. This record does not claim that intermittent issue is fixed.
