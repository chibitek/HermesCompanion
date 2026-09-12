# Companion Workspace Bridge

Hermes's API gateway exposes chat, but its project tree and Bots roster currently
live in the Desktop/TUI domain handlers. This native plugin makes those existing
read operations available on the same API listener. No Hermes core files or
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

- `GET /api/companion/projects`: profile-scoped trees from `projects.tree`.
- `GET /api/companion/project?profile=...&project_id=...`: hydrated project lanes.
- `GET /api/companion/bots`: the server's `profiles.list` roster.
- `GET /api/companion/bot-history?profile=...&offset=...`: canonical Bot Chat,
  resolved on the server, in pages of 100 messages. Arbitrary client session IDs
  are not accepted. Missing canonical chats do not fall back to unrelated chats.
- `GET /api/companion/boards`: existing Kanban boards.
- `GET /api/companion/board?board=...`: columns and tasks on one existing board.
- `GET /api/companion/task?board=...&task_id=...`: full task detail from the
  selected board, including untruncated summaries, results, comments, and runs.
  Requires bridge 0.1.2; the iOS detail screen rejects mismatched board/task IDs.

There is no arbitrary RPC forwarding, file reader, write route, or new listener.
The canonical Hermes handlers retain their own schema migration and discovery
behavior. Browser responses use `Cache-Control: no-store`. Source/profile identity
is retained rather than combining same-named projects from different profiles.
The project handlers retain Hermes's native session limits: the overview is not
a full-history export. Cross-profile Bot chat, project mutations, and Kanban
editing remain future work; Companion does not silently route these to default.

## Verify

From the Companion repository, with Hermes's Python environment:

```sh
python -m unittest discover -s GatewayPlugin -v
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
