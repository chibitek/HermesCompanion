# Companion Workspace Bridge

Version 0.1.9 adds profile-owned project management through native `projects.*`
handlers. Reads and receipts identify the profile; the phone rejects mismatches.
Native RPC errors keep their method, code, and validation reason. All routes use
the same existing root gateway authorization.

Version 0.1.8 adds native Kanban task creation, editing, transitions, and comments.
It requires deployment to expose the new write routes. The iOS editors check the
capability response before enabling Save. Task mutations use the existing root
gateway authorization and native workflow validation. No live tasks are written
by the automated tests.

Version 0.1.7 adds `GET /api/companion/changes`, an authenticated SSE invalidation
feed. It samples server-owned state files once per second and emits opaque
revision tokens, with five-second keepalives. It never sends file contents or
accepts client-supplied paths. Native read endpoints remain authoritative.
The iOS app refreshes open workspace views after changes; gateways without this
version retain periodic sync. This is persisted-state sync, not a relay for
unpersisted desktop drafts or token streams. See
[the current verification record](../docs/SYNC_REPAIR_VERIFICATION.md).


Hermes's API gateway exposes chat, but its project tree and Bots roster currently
live in the Desktop/TUI domain handlers. This native plugin makes those existing
workspace operations available on the same API listener. No Hermes core files or
credential storage are modified. Tested against Hermes 0.21.2.

## Install

Copy `hermes-companion` into the connected machine's `$HERMES_HOME/plugins/`, then
run `hermes plugins enable hermes-companion` and restart that Hermes gateway when
it has no active turns. Installation is required on each connected server; an
iOS update alone cannot add server endpoints. To remove access, disable the
plugin with `hermes plugins disable hermes-companion` and restart the gateway.

The root gateway key authorizes these routes, including the all-profile project
and Bot metadata. Only enable this on an operator-owned gateway whose root API
key holders are allowed to see those profiles. No `/p/<profile>` aliases are
registered, so a named-profile credential cannot use that alias to read other
profiles. The plugin uses the gateway's existing authorization check unchanged.

## Routes

- `GET /api/companion/project-records?profile=...`: saved project records and active ID.
- `GET /api/companion/project-record?profile=...&project_id=...`: one saved project.
- `POST /api/companion/projects-create?profile=...`: name, optional description,
  slug, folders, primary path, icon, color and board slug. Hermes has no creation
  idempotency key; the phone requires a list refresh after an uncertain response.
- `PATCH /api/companion/project-record?profile=...&project_id=...`: changed name,
  description, icon, color or board slug; empty strings clear optional fields.
- `DELETE /api/companion/project-record?profile=...&project_id=...`: delete the
  saved record and folder links, retaining files and conversations. Clear its
  active selection first; the native deletion handler otherwise leaves a stale pointer.
- `POST /api/companion/project-folder?profile=...&project_id=...`: path, optional
  label and primary flag. Reusing an existing path updates its label.
- `DELETE /api/companion/project-folder?profile=...&project_id=...`: remove a linked path.
- `POST /api/companion/project-primary?profile=...&project_id=...`: select a linked path.
- `POST /api/companion/project-archive?profile=...&project_id=...`: archive, or `restore: true`.
- `POST /api/companion/project-active?profile=...&project_id=...`: select an active
  project; omit the ID to clear it. Folder inputs use absolute server paths or `~/`.
- `GET /api/companion/projects`: profile-scoped trees from `projects.tree`.
- `GET /api/companion/project?profile=...&project_id=...`: hydrated project lanes.
  Bridge 0.1.5 also preserves discovered empty repositories omitted by native
  drill-in, using the exact same-profile overview record with zero sessions.
  A nonempty overview is never substituted for hydrated history.
- `GET /api/companion/project-history?profile=...&project_id=...&session_id=...&offset=...`:
  profile-owned history in pages of 100, after validating current project
  membership. Uses Hermes's resume resolution and display projection. Requires
  bridge 0.1.3. Sessions outside the loaded default-profile chat list now open
  this read-only history instead of appearing as noninteractive labels.
- `GET /api/companion/bots`: the server's `profiles.list` roster.
- `GET /api/companion/bot-history?profile=...&offset=...`: canonical Bot Chat,
  resolved on the server, in pages of 100 messages. Arbitrary client session IDs
  are not accepted. Missing canonical chats do not fall back to unrelated chats.
- `GET /api/companion/boards`: existing Kanban boards.
- `GET /api/companion/board?board=...`: columns and tasks on one existing board.
- `GET /api/companion/task?board=...&task_id=...`: full task detail from the
  selected board, including untruncated summaries, results, comments, and runs.
  Requires bridge 0.1.2; the iOS detail screen rejects mismatched board/task IDs.
  The native detail screen also traverses dependencies and child tasks on the
  same board, displaying full child summaries/results. Unlinked child-result
  records are rejected rather than rendered under an unrelated parent.

- `GET /api/companion/task-attachment?board=...&task_id=...&attachment_id=...`:
  downloads an attachment belonging to that task. Requires bridge 0.1.4. Hermes's
  native download handler retains its board-directory containment checks. The
  client does not follow redirects, verifies the reported byte count, uses an
  isolated temporary directory, and previews with Quick Look.

- `GET /api/companion/capabilities`: bridge version and supported task operations/statuses.
- `POST /api/companion/tasks?board=...`: create with a title and stable
  `idempotency_key`; uses native `CreateTaskBody`. The phone defaults to triage.
- `PATCH /api/companion/task?board=...&task_id=...`: explicit changed fields using
  native `UpdateTaskBody`. Result/summary/reason require their native transitions.
  Native worker ownership and dependency refusals keep their status and reason.
- `POST /api/companion/task-comment?board=...&task_id=...`: add a nonempty body
  attributed to Companion. Comments have no automatic retry or idempotency;
  inspect the task after an uncertain response before submitting again.

There is no arbitrary RPC forwarding, arbitrary file reader, or new listener.
The canonical Hermes handlers retain their own schema migration and discovery
behavior. Browser responses use `Cache-Control: no-store`. Source/profile identity
is retained rather than combining same-named projects from different profiles.
Bridge 0.1.6 sizes native tree requests using each profile's read-only total
session count instead of the 2,000/5,000-row defaults. Native filtering and
grouping still apply; counts and trees are separate reads, not an atomic
cross-profile snapshot or full-history export. Cross-profile Bot chat and
advanced Kanban operations remain future work. Task edits update only supplied
fields; they are not compare-and-swap transactions against concurrent Mac edits.
Project history is limited to sessions Hermes includes in the hydrated project
tree. Membership is rechecked on each page; moving a session out of that project
makes the old project-history route unavailable rather than silently rerouting it.

## Verify

From the Companion repository, with Hermes's Python environment:

```sh
PYTHONPATH=/path/to/hermes-agent /path/to/hermes-agent/.venv/bin/python -m unittest discover -s GatewayPlugin -v
hermes plugins validate GatewayPlugin/hermes-companion
```

The native plugin depends on Hermes's current project/profile RPC and Kanban
domain handlers. Revalidate it after upstream updates. Unavailable handlers return
an error, not a fabricated empty workspace. The iOS views show failures and retry,
poll every 30 seconds while active, and discard responses from replaced views.
Open Bot details also refresh their model/profile metadata from the roster.
Missing profiles are shown as unavailable, and conversation previews use only
the canonical Bot Chat, never an unrelated last session. A failed workspace
refresh clears the old snapshot so removed resources do not remain actionable.
Older Bot history pages refresh manually to avoid shifting while being read.

Bridge 0.1.2 verification: nine route/domain contract tests passed. The new task
reader was also exercised against all six existing tasks across the live server's
boards, checking returned board, task, comment, and run ownership. This was a
direct domain read, not a claim that the new route has been deployed. The iOS
test suite passed with full-text retention and ownership regression coverage.

Bridge 0.1.3 verification: ten bridge tests and 60 iOS tests passed. Direct
project-history reads succeeded for four real profiles containing project
sessions, with matching requested session and response owner. Tests cover
foreign project membership rejection, negative offsets, and client checks for
wrong owner/project/session/page while permitting Hermes-resolved resume IDs.
The 0.1.3 route and iOS changes require deployment; direct domain verification
does not establish installation on a phone or remote gateway.

Bridge 0.1.8 verification: 23 tests passed, including native SQLite round trips
in a disposable `HERMES_KANBAN_HOME`. These check duplicate-create protection,
phone writes read through native handlers, native writes read through the phone
route, authentication before mutation, rejected statuses, malformed fields, and
missing board/task rejection. No running gateway or live board was modified.

Bridge 0.1.9 verification: 28 bridge tests passed, including native project RPC
round trips in two disposable profile homes. They verify profile isolation,
folder/primary updates, archive/restore, active selection, native duplicate-folder
errors, and project deletion retaining server files. These are not live gateway
or phone deployment checks. Profile records and filesystem changes are not one
atomic snapshot; concurrent writers still require ordinary reconciliation.
