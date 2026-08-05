# Hermes Companion vs. Hermes WebUI — Parity Analysis

Comparison of this iOS app against [nesquena/hermes-webui](https://github.com/nesquena/hermes-webui),
the self-hosted browser front-end for Hermes Agent.

Last reviewed: 2026-08-05 (upstream `main`, this repo at `1294cb4`).

---

## 1. They are not the same kind of client

This matters more than any individual feature, because it determines which gaps
are "write some SwiftUI" and which are "no API exists yet."

| | Hermes WebUI | Hermes Companion |
|---|---|---|
| Runs | Python server on the same box as the agent (default `:8787`) | iOS app on a phone |
| Agent access | **In-process** — imports the agent, reads `HERMES_HOME` config, touches the filesystem directly | **Over the network** — HTTP to a Hermes Agent Gateway (`:8642`/`:8643`) |
| Reach | Anything on the host: files, cron, `MEMORY.md`, profile `config.yaml`, git, shells | Only what the gateway exposes over HTTP |
| Delivery | `git clone` + `bootstrap.py` | App Store binary over a Tailscale tunnel |

WebUI is effectively a local control panel with an agent embedded in it. Companion
is a remote thin client. So a large share of WebUI's feature list — the workspace
file browser, cron editing, memory editing, profile switching, the web terminal —
is *filesystem work on the agent host*, not chat work. Those aren't features we
forgot to build; they're features that currently have no gateway endpoint to call.

Endpoints this app actually uses today (`Sources/HermesAPIClient.swift`):
`/health`, `/v1/capabilities`, `/v1/models`, `/v1/skills`, `/v1/toolsets`,
`/api/sessions` (list/create/get/patch/delete/fork), `/api/sessions/{id}/messages`,
`/api/sessions/{id}/chat`, `/api/sessions/{id}/chat/stream`, `/model`.

Upstream's own gateway client (`api/gateway_chat.py`) only reaches for
`/v1/runs`, `/v1/runs/{id}/events`, `/v1/runs/{id}/stop`, and
`/v1/chat/completions` — i.e. even upstream treats the gateway as chat-only.
Everything else it does, it does locally.

---

## 2. Where we are at parity

- Streaming chat over SSE with live token rendering
- Tool call visibility during a turn
- Tool approval cards (allow/deny before execution)
- Reasoning/thinking display
- Multi-provider model selection sourced live from the server, with favorites
- Skills browsing and `/`-triggered skill invocation from the composer
- Toolsets listing
- Session list, create, rename, delete, search, fork/duplicate
- Session projects (named grouping) — ours are local-only, see §4
- File and image attachments
- Voice input with on-device transcription
- Multiple themes with instant switching
- Auth against a protected server (Keychain-stored bearer token)
- Queue-while-streaming and stop-generation from the composer
  (`ComposerSubmissionLogic`)
- Session persistence + reconnect across app/tunnel interruptions

---

## 3. Where we are ahead

Not everything is a deficit. Companion does things WebUI structurally cannot:

- **Hermes Talk** — full-screen 2-way voice conversation mode. WebUI's voice is
  dictation-into-the-textarea via the Web Speech API; there is no conversational
  voice loop, no TTS playback, no visualizer.
- **"Hey Hermes" wake phrase** — hands-free activation with no screen touch.
- **ElevenLabs TTS** with configurable voice/speed/pitch.
- **CarPlay** voice mode.
- **iOS Control Center toggle** backed by App Group shared storage.
- **Camera capture** in-composer with automatic JPEG conversion for vision APIs.
- **Multi-server switching** — Companion holds N gateways with independent
  credentials, sessions, and preferences. WebUI is one install per agent host;
  the closest analogue is profiles, which is a different axis (one host, many
  agent configs).
- **Native mobile everything** — Keychain, background/foreground reconnection,
  Tailscale awareness, screen-wake management, splash, release-notes popup.

---

## 4. Gaps — chat surface

These are the highest-value gaps because they need **no new gateway API**. It is
all client-side rendering of data we already receive.

| Gap | Upstream behavior | Our state | Notes |
|---|---|---|---|
| **Full Markdown rendering** | Headings, lists, tables, blockquotes, nested structure | `GlassBubble.swift:97` parses with `.inlineOnlyPreservingWhitespace` — **bold/italic/inline-code only**. Headings, lists, and tables render as literal text. | Biggest single readability gap. Already scoped in `ROADMAP.md` §2.1 and still unimplemented. |
| **Code blocks** | Fenced blocks with Prism.js syntax highlighting, per-block copy button, horizontal scroll | None — fenced code renders as an undifferentiated run of text | Agent output is code-heavy; this compounds with the Markdown gap. |
| **Copy affordances** | Copy button on every code block, with confirmation | Text is selectable; no explicit copy control | |
| **Edit + regenerate** | Edit any past user message inline, re-run from that point | Not present | Needs a gateway-side "truncate + resend" path or client-side resend from index. |
| **Retry last response** | One click to regenerate the last assistant turn | Not present | |
| **Context/token meter** | Live ring in the composer footer: tokens used, cost estimate, model-aware fill | Token fields exist in `Models.swift` but no in-chat indicator | Cheap win — the data is already on the wire. |
| **Message timestamps** | Per-message HH:MM, full date on hover | Setting exists in appearance; verify it is surfaced per message | |
| **Subagent cards** | Delegated child-agent activity drawn with its own icon and indent | Not distinguished from ordinary tool calls | |
| **Mermaid diagrams** | Rendered inline (flowchart/sequence/gantt) | Not rendered | Low priority on a phone screen. |
| **Math (KaTeX)** | Vendored KaTeX 0.16.22, inline + block | Not rendered | Low priority. |
| **Jump-to-bottom / scroll anchoring** | Preserves position when reading history | Auto-scrolls to bottom | Scoped in `ROADMAP.md` §2.3, unimplemented. |
| **In-conversation search** | Search message *content*, not just titles | `SessionPickerView` searches titles/source/id/project only | Scoped in `ROADMAP.md` §2.5, unimplemented. |
| **Message context menu** | Copy / copy-as-markdown / share / regenerate / delete | Not present | Scoped in `ROADMAP.md` §2.4, unimplemented. |
| **Slash commands** | `/help` `/clear` `/compress` `/compact` `/model` `/workspace` `/new` `/usage` `/theme`, with autocomplete | `/` opens the **skills** picker only (`SkillCommandLogic`) | Several of these (`/model`, `/theme`, `/new`, `/clear`) are pure client actions we could handle locally without touching the gateway. |

---

## 5. Gaps — session management

| Gap | Upstream | Our state |
|---|---|---|
| Pin / star to top | Yes, gold indicator | No |
| Archive (hide without deleting) | Yes, with show-archived toggle | No |
| Tags (`#tag` in title → colored chips, click to filter) | Yes | No |
| Date grouping (Today / Yesterday / Earlier, collapsible) | Yes | Flat list |
| Export as Markdown transcript | Yes | No |
| Export/import as JSON | Yes | No |
| Public read-only share link | Yes (`api/shares.py`) | No — server-side feature, needs a gateway endpoint |
| CLI session bridge (agent SQLite sessions in the list with a `cli` badge) | Yes | No — we list only what `/api/sessions` returns |
| Per-conversation token/cost readout | Yes | Partial (fields parsed, not shown) |
| Projects | Server-persisted, shared across clients, colored | **Local-only** — `ProjectStore` writes to `UserDefaults`, so project assignments do not survive a reinstall and are invisible to WebUI/CLI |

The projects divergence is worth a decision: either accept it as a phone-local
organizing tool and say so in the UI, or move it behind a gateway API so all
surfaces agree.

---

## 6. Gaps — panels we have no equivalent for

Upstream ships eleven left-rail panels: `chat`, `tasks`, `skills`, `memory`,
`profiles`, `todos`, `workspaces`, `kanban`, `insights`, `logs`, `settings`.
We ship the equivalent of two (chat, settings) plus read-only skills.

| Panel | What it does upstream | Blocker for us |
|---|---|---|
| **Workspace file browser** | Tree, breadcrumbs, inline preview of text/code/Markdown/images, create/edit/rename/delete, folder creation, binary download, git branch + dirty-count badge, `workspace://` links from chat | No gateway file API. Highest-effort, highest-value gap if we ever want the app to be more than a chat client. |
| **Tasks (cron)** | List/create/edit/run/pause/delete cron jobs, run history, completion alerts | No gateway cron API. On iOS this pairs naturally with push notifications — see below. |
| **Memory** | View and edit `MEMORY.md` / `USER.md` inline | No gateway memory API. |
| **Profiles** | Create/switch/delete agent profiles, clone config, per-profile gateway status, custom endpoint fields | No gateway profile API. Partially overlapped by our multi-server switcher, but not the same thing. |
| **Todos** | Live task list for the current session | Possibly derivable from stream events; needs checking against gateway event types. |
| **Spaces/workspaces** | Add/rename/remove workspaces, quick-switch | No gateway API. |
| **Skills authoring** | Create/edit/delete skills, category browse, linked-file viewer | We are **read-only**: browse and invoke. Write path needs an API. |
| **Kanban / Insights / Logs** | Board bridge, usage insights, server logs | Server-local; low mobile value. |
| **Terminal** | Web terminal against the agent host (`api/terminal.py`) | Out of scope for a phone, in my view. |

---

## 7. Gaps — platform and polish

| Gap | Upstream | Our state |
|---|---|---|
| Localization | i18n with en/es/de/it/ja/ru/zh and more | English only |
| Accessibility of send behavior | Configurable send key | We have enter-key-sends config — parity |
| Push/alerting | Toast + unread badges for cron completion and background-session errors | None. **This is the natural iOS advantage we are leaving on the table** — an agent that finishes a job while your phone is in your pocket should be able to tell you. Already listed in our README roadmap as "push notifications for tool approval requests"; the cron-completion case is at least as valuable. |
| iPad / split view | Desktop three-panel layout | iPhone-only layout; iPad listed as roadmap |

---

## 8. Suggested ordering

**Tier 1 — client-side only, ship-now value:**
1. Full Markdown rendering + fenced code blocks with syntax highlighting and copy
2. Context/token meter in the composer
3. Message context menu (copy / share / regenerate)
4. Jump-to-bottom + scroll anchoring
5. Local slash commands (`/new`, `/clear`, `/model`, `/theme`, `/usage`)

**Tier 2 — client-side, session ergonomics:**
6. Pin, archive, date grouping, tags
7. In-conversation content search
8. Markdown transcript export (share sheet)
9. Decide the projects question — local-only vs. server-backed

**Tier 3 — needs gateway API work (or an app-side agreement with the agent):**
10. Push notifications for approvals and cron completion
11. Workspace file browsing (read-only preview first)
12. Tasks/cron read-only view, then edit
13. Memory view/edit
14. Skills authoring

**Probably never (accept the divergence):** web terminal, kanban, logs,
insights, Nix/Docker deployment concerns, OIDC/passkey login (Keychain +
Tailscale already covers our threat model).

---

## 9. Caveats

- Upstream's `README.md` was the primary source for its feature list; some
  entries were spot-checked against `static/` and `api/` but not all were
  exercised against a running server.
- Gateway capability claims here are inferred from what this app calls and what
  upstream's `api/gateway_chat.py` calls. If the Hermes Agent gateway has since
  grown file/cron/memory endpoints, several Tier 3 items get much cheaper — that
  is worth confirming against the current hermes-agent source before planning.
