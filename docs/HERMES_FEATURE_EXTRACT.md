# Hermes Agent Feature Extraction

Original analysis: `NousResearch/hermes-agent` at `04dd80a977`, Hermes 0.21.1,
Companion 1.8.48 (134). The tables below are the historical extraction plan,
not a claim that every listed capability has shipped.

## September 11 Update

Verified installed Hermes `53e32d0581` (0.21.2) against Companion 1.8.62 (155).
The API listener still does not natively mount the complete project/Bot/Kanban
interfaces. `GatewayPlugin/hermes-companion` now exposes five read endpoints
using existing Hermes project/profile RPC and Kanban domain handlers. Native
Projects, Bots, and Kanban tabs consume these endpoints, retaining profile IDs
and showing errors instead of guessing from session counts. The bridge is an
operator-installed component, not an assumption about hosted Hermes support.

Live verification: ten profile project trees without read errors, ten Bot
profiles, two boards, successful project/board detail decoding, and HTTP 401
without authorization. Test coverage: 54 iOS unit tests and three bridge route
tests pass. Cross-profile Bot conversation, project mutations, full task results,
and Kanban editing remain open. See `GatewayPlugin/README.md` for installation,
access scope, upstream dependencies, and native session-limit caveats.

Build 156 adds canonical Bot history through a sixth bridge endpoint. The server
resolves the Bot's conversation pointer, follows Hermes's resume resolution, and
uses the existing profile-aware, paginated message reader. The client rejects
foreign-profile/page responses and respects hidden/display-projected compaction
messages. Verification: all ten live profile responses decoded, authenticated
HTTP 200 with matching owner, unknown profile HTTP 400, unauthenticated HTTP 401,
56 iOS tests and seven bridge tests passed. This does not implement cross-profile
message submission or change profile authentication.

## Decision framework

### Cross-Profile Messaging Verification

September 11, 2026: read-only live probes of `/p/<profile>/api/sessions?limit=1`
returned HTTP 200 for `default` and HTTP 404 for all nine other roster profiles.
The installed configuration does not set `gateway.multiplex_profiles`.
This is a serving boundary, not evidence that those profiles have no sessions.
The Companion bridge can read their project/Bot history through profile-aware
domain readers, but that does not establish a valid chat transport for them.

The installed Hermes API implements profile-prefixed native session/chat routes
in `gateway/platforms/api_server.py`. `_resolve_request_profile` rejects profiles
that the gateway is not configured to serve. `_make_profile_prefix_middleware`
then enters the selected profile's runtime scope. Do not bypass this boundary by
passing a different profile's session ID to the default chat endpoint.

The dashboard's alternative chat transport is not a drop-in REST send: its
`hermes_cli/web_server_chat.py::_resolve_chat_argv` launches a profile-scoped
process, and `hermes_cli/web_routers/chat_ws.py` owns its WebSocket lifecycle.
Wrapping a generic subprocess or forwarding arbitrary RPC would bypass existing
admission, cancellation, authorization, and session ownership behavior.

Next messaging work must use a verified native profile transport and preserve
the canonical conversation pointer and session model. Enabling multi-profile
serving is an operator configuration change requiring approval, followed by
per-profile credential/route verification, stream cancellation/reconnect tests,
and on-device confirmation. No authentication or token storage changes have
been made, and no non-default chat requests were submitted during these probes.

Hermes Agent separates a narrow agent core from broad client-facing surfaces. Hermes Companion should follow the same boundary. The app should not duplicate the agent loop, memory engine, or terminal. It should expose selected gateway capabilities through mobile-native workflows.

Adopt a feature only when it satisfies one of these:

1. It improves remote operation of an already-running Hermes gateway.
2. It has a stable REST or SSE contract exposed by `/v1/capabilities`.
3. It is desktop/dashboard-only but valuable enough to justify adding a second Hermes dashboard client.
4. It is better on iOS than on desktop, such as notifications, widgets, Live Activities, CarPlay, or voice.

Do not extract:

- Full desktop plugin management.
- The Electron/TUI UI layer.
- Server-side TTS or speech transcription as a default while iOS local voice is the product differentiator.
- Broad configuration or secret editing from a phone.
- Core agent behavior or a second agent runtime.

## Current Companion baseline

Already implemented:

- Multi-server connections, server health, and recovery on the selected gateway. Automatic fallback to unrelated saved servers was removed in the September 13 connection repair.
- Session listing, creation, history, rename, delete, and fork.
- Streaming session chat with assistant deltas, thinking, and tool events.
- Session-backed model locking.
- Full provider and model catalog from `/api/model/options`.
- Skills and toolsets read-only lists.
- Image, camera, and document attachments.
- Local speech recognition, local TTS, wake phrase, CarPlay, and Control Center voice activation.
- Themes, appearance controls, markdown rendering, message queueing, and stream watchdog.
- Local per-server project folders and stale session cleanup.

Companion is already ahead of the desktop client on mobile-specific voice, wake phrase, CarPlay, Control Center, multi-server switching, and native attachments.

## Tier 1: Extract through the API server now

These routes are already exposed by the API server and advertised in `/v1/capabilities`. They should be added before opening a second dashboard connection.

| Feature | Upstream contract | Companion value | Priority |
|---|---|---|---|
| Feature-gated UI | `GET /v1/capabilities` | Hide unavailable features and avoid hard-coded version checks | High |
| Deep health | `GET /health/detailed` | Show gateway readiness and failed components | Medium |
| Session archive/pin/unread | `PATCH /api/sessions/{id}` | Native history triage without deleting sessions | High |
| Session statistics | `GET /api/sessions/{id}` | Show tokens, cost, tool calls, model, lineage | High |
| Paginated messages | `GET /api/sessions/{id}/messages` | Load long conversations efficiently | High |
| Session continuity | `X-Hermes-Session-Id`, `X-Hermes-Session-Key` | Keep identity stable across reconnects and route memory correctly | High |
| Reasoning/service tier | `model_options` in chat request | Make the existing reasoning selector real where the server supports it | Medium |
| Async runs | `POST /v1/runs` | Start long tasks and let the phone sleep | High |
| Run status | `GET /v1/runs/{run_id}` | Durable background task status | High |
| Run events | `GET /v1/runs/{run_id}/events` | Live tool progress and assistant deltas for background runs | High |
| Run stop | `POST /v1/runs/{run_id}/stop` | Cancel runaway background work | High |
| Run steering | `POST /v1/runs/{run_id}/steer` | Correct a long task without restarting it | Medium |
| Run approvals | `POST /v1/runs/{run_id}/approval` | Approve or deny tool execution from the phone | High |
| Cron jobs | `/api/jobs` and job subroutes | View, create, edit, pause, resume, run, and delete scheduled tasks | High |
| Artifacts | `POST /v1/artifacts/upload`, `GET /v1/artifacts/download/{id}` | Send larger files and retrieve generated artifacts | High |
| Browser control | `/v1/browser-control/register`, `/v1/browser-control/ws` | Optional remote browser control when the gateway enables it | Medium |
| Skills catalog | `GET /v1/skills` | Better search, categories, detail, and one-tap `/skill` invocation | Medium |
| Toolsets catalog | `GET /v1/toolsets` | Show enabled/configured tools and per-tool surface | Medium |
| Model catalog refresh | `GET /api/model/options?refresh=1` | Force refresh without reconnecting | Low |

## Tier 2: Extract through the Hermes dashboard server

These routes exist in `hermes_cli/web_routers`, but the API server on 8642 does not mount all of them. Companion can either connect to a user-started dashboard server or ask Hermes upstream for REST parity. These are high-value but need a separate dashboard base URL or upstream support.

### Projects and repositories

| Capability | Dashboard surface | Companion value |
|---|---|---|
| Server-side project tree | `GET /api/profiles/projects/tree` | Replace or augment local project folders |
| Project CRUD | `projects.*` JSON-RPC and project database | Create and manage real Hermes projects |
| Folder management | `projects.add_folder`, `remove_folder`, `set_primary` | Match desktop project organization |
| Active project | `projects.set_active`, `projects.for_cwd` | Start sessions in the right workspace |
| Repo discovery | project tree and discovered repos | Show repositories with zero sessions |
| Git status and worktrees | `/api/git/status`, `/api/git/worktrees` | Mobile repo health view |
| Branches and PR review | `/api/git/branches`, `/api/git/review/*` | Review diffs and PRs from the phone |

### Advanced sessions

| Capability | Dashboard surface | Companion value |
|---|---|---|
| Session search | `GET /api/sessions/search` | Search titles and transcripts across sessions |
| Bulk delete/prune | `/api/sessions/bulk-delete`, `/api/sessions/prune` | Safe cleanup from mobile |
| Empty-session cleanup | `/api/sessions/empty/count`, `DELETE /api/sessions/empty` | Remove throwaway sessions |
| Import/export | `/api/sessions/import`, `/api/sessions/{id}/export` | Move or back up conversations |
| Session stats | `GET /api/sessions/stats` | Aggregate token, cost, and tool usage |
| Latest descendant | `GET /api/sessions/{id}/latest-descendant` | Follow compression and fork lineage correctly |
| Cross-profile sessions | `/api/profiles/sessions`, `/api/profiles/sessions/sidebar` | Browse multiple Hermes profiles |

### Profiles

| Capability | Dashboard surface | Companion value |
|---|---|---|
| List profiles | `GET /api/profiles` | Second-level switcher under each server |
| Active profile | `GET/POST /api/profiles/active` | Scope sessions and models to a profile |
| Profile identity | `/api/profiles/{name}/soul`, `/description` | View or edit profile persona |
| Profile model | `PUT /api/profiles/{name}/model` | Per-profile model defaults |
| Export/import | `/api/profiles/{name}/export`, `/api/profiles/import` | Move profiles between servers |

### Files and workspace

| Capability | Dashboard surface | Companion value |
|---|---|---|
| File browser | `/api/files`, `/api/fs/list` | Browse server files and projects |
| Read/write text | `/api/fs/read-text`, `/api/fs/write-text` | Edit small files from mobile |
| Upload/download | `/api/files/upload`, `/api/files/download` | Better attachment and artifact workflow |
| Media browsing | `/api/media` | View generated media and screenshots |
| Default working directory | `/api/fs/default-cwd`, `/api/fs/git-root` | Start work in the right folder |

### Models, providers, and local models

| Capability | Dashboard surface | Companion value |
|---|---|---|
| Model info | `GET /api/model/info` | Show context window and capabilities |
| Recommended default | `GET /api/model/recommended-default` | Better onboarding for a provider |
| Auxiliary models | `GET /api/model/auxiliary` | Show task-specific routing |
| Mixture of Agents | `/api/model/moa` | Advanced model orchestration |
| Provider OAuth | `/api/providers/oauth/*` | Add providers without copying keys |
| Custom endpoints | `/api/providers/custom-endpoints/*` | Configure OpenAI-compatible endpoints |
| Local model catalog | `/api/local-models/*` | Manage local models on the gateway |

### Skills, tools, MCP, and memory

| Capability | Dashboard surface | Companion value |
|---|---|---|
| Skill detail/edit | `/api/skills/content`, `POST /api/skills`, `PUT /api/skills/content` | Inspect or edit skills from the phone |
| Skill toggle | `PUT /api/skills/toggle` | Enable or disable a skill remotely |
| Skills Hub | `/api/skills/hub/*` | Discover, install, update, and uninstall skills |
| Toolset configuration | `/api/tools/toolsets/*` | Configure and toggle toolsets remotely |
| Terminal backend | `/api/tools/terminal/backends`, `PUT /api/tools/terminal/backend` | Choose local, SSH, Docker, or sandbox execution |
| MCP management | `/api/mcp/servers`, `/api/mcp/catalog` | Manage MCP servers and catalogs |
| Memory providers | `/api/memory/providers/*` | Configure persistent memory backends |
| Curator and learning graph | `/api/curator`, `/api/learning/graph` | Visualize the agent learning loop |
| Wisdom pipeline | `/api/wisdom/*` | Review and install learned skills |

### Messaging, operations, and analytics

| Capability | Dashboard surface | Companion value |
|---|---|---|
| Platform management | `/api/messaging/platforms` | View and configure Telegram, Discord, Slack, WhatsApp, Signal |
| Platform onboarding | WhatsApp/Telegram onboarding routes | Pair messaging platforms from mobile |
| Server status | `GET /api/status`, `GET /api/system/stats` | Gateway dashboard on the phone |
| Logs | `GET /api/logs` | Diagnose failures remotely |
| Gateway actions | `/api/gateway/restart`, `/api/gateway/drain` | Controlled recovery |
| Update check | `/api/hermes/update/check`, `POST /api/hermes/update` | Update Hermes from the phone |
| Pairing and webhooks | `/api/pairing`, `/api/webhooks` | Manage inbound access |
| Usage analytics | `/api/analytics/usage`, `/api/analytics/models` | Cost and model usage dashboard |
| Audio relay | `/api/audio/*` | Optional server transcription or TTS fallback |

## Tier 3: Extract through the desktop JSON-RPC socket

The desktop app and TUI use `/api/ws` JSON-RPC. These capabilities are valuable but should come after stable REST support because they require a WebSocket client, request/response IDs, notifications, and reconnect handling.

| Surface | Representative methods | Mobile value |
|---|---|---|
| Projects | `projects.list`, `projects.create`, `projects.tree`, `projects.project_sessions` | Real server projects and repo grouping |
| Session control | `session.create`, `session.resume`, `session.activate`, `session.branch`, `session.compress`, `session.close` | Full desktop session parity |
| Session correction | `session.undo`, `session.steer`, `session.redirect`, `session.interrupt` | Mobile equivalent of CLI steering |
| Session telemetry | `session.usage`, `session.context_breakdown`, `session.events.since`, `session.events.stats` | Context, usage, and event inspection |
| Prompt and attachments | `prompt.submit`, `image.attach`, `pdf.attach`, `file.attach`, `clipboard.paste` | Desktop-grade prompt workflow |
| Approvals | `approval.pending`, `approval.received`, `approval.respond` | Fine-grained command approval |
| Slash commands | `slash.exec`, `command.dispatch`, `complete.slash` | Run Hermes commands from the phone |
| Shell and CLI | `shell.exec`, `cli.exec` | Advanced maintenance, carefully permission-gated |
| Browser | `browser.manage`, `browser.controller.*` | Remote browser sessions |
| Subagents | `subagent.list`, `subagent.tail`, `subagent.interrupt`, `subagent.steer`, `delegation.status` | Observe parallel agent work |
| Spawn trees | `spawn_tree.save`, `spawn_tree.list`, `spawn_tree.load` | Resume complex delegated work |
| Image generation | `image.generate` | Native image-generation UI |
| Voice/wake | `wake.start`, `wake.stop`, `wake.status`, `voice.record`, `voice.tts` | Optional server voice integration |
| Hosted rooms | `groups.list`, `groups.state`, `groups.approve`, `groups.stop` | Multi-agent or hosted-room control |
| Connectors and bot relay | `connectors.list`, `connectors.connect`, `bot_relay.*` | Manage external agent connections |
| Vault | `vault.list`, `vault.unlock`, `vault.add`, `vault.remove` | Secret-source status, with strong UI gating |
| Billing/free tier | `billing.state`, `subscription.preview`, `free_tier.status` | Provider account and entitlement awareness |
| Pets | `pet.info`, `pet.gallery`, `pet.generate`, `pet.select` | Optional playful companion feature |

## Recommended implementation order

### Phase 1: Mobile remote control

1. Add a `FeatureRegistry` backed by `/v1/capabilities`.
2. Improve session management: archive, pin, unread, lineage, stats, and message pagination.
3. Add async runs with status, events, stop, steering, and approvals.
4. Add cron-job management.
5. Add artifact upload/download to the existing attachment flow.
6. Surface toolsets and skills with better search and detail.

### Phase 2: Operational dashboard

1. Add server diagnostics with `/health/detailed` and, when available, `/api/status`.
2. Add jobs, usage, and model analytics.
3. Add optional server log viewing.
4. Add controlled gateway restart/drain/update actions.
5. Add a messaging-platform status screen.

### Phase 3: Workspace and projects

1. Add a dashboard-server connection type or use a new upstream REST contract for project data.
2. Replace local project folders with server project tree data while retaining local tags as fallback.
3. Add repo health, worktrees, branches, and PR review.
4. Add file browsing and small-file editing.

### Phase 4: Deep desktop parity

1. Add a Hermes JSON-RPC WebSocket client.
2. Add session correction, compression, branching, usage, and event inspection.
3. Add subagent and delegation observability.
4. Add MCP, Skills Hub, toolset configuration, and provider OAuth.
5. Consider hosted rooms, connectors, and pets only after core parity is stable.

## Architecture recommendations

1. Split `AppStore` into focused stores: `ConnectionStore`, `SessionStore`, `ModelStore`, `RunStore`, `JobStore`, and `FeatureRegistry`.
2. Keep `HermesAPIClient` as the REST/SSE client and add a separate `HermesRPCClient` for `/api/ws`.
3. Gate every feature on `/v1/capabilities` rather than Hermes version strings.
4. Preserve per-server preferences for every new feature.
5. Treat destructive server actions, config edits, vault access, and gateway restarts as opt-in and explicitly confirmed.
6. Use Live Activities and local notifications for background runs and approvals.
7. Keep iOS voice, wake phrase, CarPlay, and Control Center as native differentiators; do not replace them with server audio by default.

## Highest-value first ten

1. Feature-gated UI from `/v1/capabilities`.
2. Session archive, pin, unread, lineage, stats, and message pagination.
3. Async runs with durable status and live events.
4. Run approvals and stop.
5. Cron-job management.
6. Artifact upload/download.
7. Better skills and toolsets browsing.
8. Server diagnostics and health detail.
9. Project/repo tree through the dashboard or a new upstream REST contract.
10. Usage and cost analytics.

This order gives Hermes Companion the largest amount of real Hermes Agent capability without turning the iOS app into a second desktop UI.
