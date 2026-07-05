# Hermes Companion Development Roadmap

Branch: `feature/theme-system-and-ui-overhaul`
Created from: `Dev_Erick` (commit 534264f, working 1.0.3 build 4)
Last updated: 2026-07-04

## Current State

Working communication: non-streaming chat endpoint, connection setup, session
picker, basic settings, appearance controls (color scheme, accent color, font
size, compact mode, timestamps). Liquid Glass throughout. Version 1.0.3 (4).

The app connects, lists sessions, sends messages, and receives responses. That
is the baseline. Everything below builds on top of that.

---

## Phase 1: Theme System Overhaul

Goal: Replace the single hardcoded GlassTheme with a multi-theme engine. Users
pick from preset themes in Appearance settings. Each theme defines the full
visual identity: colors, fonts, backgrounds, bubble styles, effects.

### 1.1 Theme Protocol and Registry

Create a `Theme` protocol that any theme conforms to. A `ThemeRegistry` manages
available themes and the active selection (stored in `@AppStorage`).

What the protocol defines:

- Display name and identifier string
- Accent color, secondary accent, danger, warning colors
- Background style (gradient stops, solid color, or animated)
- Bubble background for user messages
- Bubble background for assistant messages
- Font family preference (system, monospaced, custom)
- Corner radius scale (sharp vs rounded)
- Spacing scale (compact vs spacious)
- Whether to use `.glassEffect()` or flat/opaque backgrounds
- Cursor style for streaming (blinking block, terminal cursor, pulse)
- Tool chip style (glass capsule, terminal pill, flat tag)

### 1.2 Theme Presets

Ship three themes at minimum:

**Hermes (default)**
- Current Liquid Glass look, unchanged
- Chibitek teal accent (#2DD4BF)
- Frosted glass bubbles, rounded corners, system fonts
- This is what already works. Keep it as the safe fallback.

**Cyberpunk**
- Dark base with neon accent gradients
- Primary accent: cyan (#00F0FF), secondary: magenta (#FF00E5)
- Subtle scanline overlay on background
- Glass effect with neon tint on bubbles
- Monospaced font for assistant messages (SF Mono), system font for user
- Sharper corners (radius 8-10)
- Glowing cursor effect instead of plain blink
- Tool chips as neon-bordered pills
- Inspired by Hermes Agent's own cyberpunk aesthetic

**Matrix Terminal**
- Pure black background (#000000), no gradient
- Matrix green primary (#00FF41), dim green secondary (#008F11)
- Monospaced font everywhere (SF Mono or JetBrains Mono)
- Flat opaque bubbles, no glass effect
- User bubbles: dark green tint (#00FF41 at 15% opacity), green border
- Assistant bubbles: transparent with green left border (terminal output style)
- Sharp corners (radius 4)
- Block cursor (blinking solid rectangle)
- Tool chips as flat tags with green text on black
- Optional: subtle green phosphor glow on text
- Maximum information density, minimal chrome
- This is the "terminal on your phone" theme

### 1.3 Theme Switcher UI

Update `AppearanceSettingsView`:

- Replace the current "Color Scheme" segmented picker with a theme picker at
  the top
- Theme picker shows theme name + small color preview swatch
- When a non-glass theme is selected (Matrix), hide the glass-specific toggles
  or replace them with theme-relevant options
- Keep the existing accent color picker but make it theme-aware: some themes
  lock the accent color (Matrix = green only), others allow customization
- Add a live preview area at the top showing a sample user and assistant bubble
  in the selected theme

### 1.4 Theme-Aware Components

Update every component in `GlassTheme.swift` to accept a theme parameter instead
of reading `GlassTheme` statics:

- `GlassBubble` reads bubble style, font, radius, background from active theme
- `GlassInputBar` reads input bar style from theme
- `GlassToolChip` reads chip style from theme
- `GlassThinkingIndicator` reads indicator style from theme
- `GlassApprovalCard` reads card style from theme
- `GlassButton` reads button style from theme
- `GlassConnectionCard` reads card style from theme
- `GlassSessionRow` reads row style from theme

For non-glass themes, components fall back to flat backgrounds and borders
instead of `.glassEffect()`. The `.if` modifier already supports conditional
glass application; extend it to check `theme.usesGlass`.

### 1.5 Background System

Update `ChatView` and `SettingsView` backgrounds:

- Current: hardcoded `LinearGradient` with `systemBackground`
- New: each theme provides a `backgroundView` that returns a `Color` or `View`
- Matrix: solid black, optional scanline overlay
- Cyberpunk: dark gradient with subtle noise
- Hermes: current gradient

### 1.6 Files to Create

- `Sources/Themes/Theme.swift` - Theme protocol
- `Sources/Themes/ThemeRegistry.swift` - Registry + AppStorage integration
- `Sources/Themes/HermesTheme.swift` - Default Liquid Glass theme
- `Sources/Themes/CyberpunkTheme.swift` - Cyberpunk neon theme
- `Sources/Themes/MatrixTheme.swift` - Matrix terminal theme

### 1.7 Files to Modify

- `Sources/GlassTheme.swift` - Refactor statics into theme-conforming structs,
  make components theme-aware
- `Sources/AppearanceSettings.swift` - Add `activeTheme` property, wire registry
- `Sources/AppearanceSettingsView.swift` - Add theme picker, live preview,
  theme-aware controls
- `Sources/ChatView.swift` - Use theme background, pass theme to components
- `Sources/SettingsView.swift` - Use theme background, pass theme to components
- `Sources/SessionPickerView.swift` - Use theme background, pass theme to rows
- `Sources/HermesCompanionApp.swift` - Inject active theme as environment object
- `Sources/ConnectionSetupView.swift` - Theme-aware styling

---

## Phase 2: Readability and Information Density

Goal: Make the app better at displaying large amounts of text, especially for
the Matrix and Cyberpunk themes where information density is the priority.

### 2.1 Markdown Rendering

Currently messages render as plain `Text(content)`. Hermes responses include
markdown (headers, code blocks, lists, bold, inline code).

Add a markdown renderer:

- Use SwiftUI's `Text` with `.markdown` attributed string support (iOS 26+
  supports basic markdown via `AttributedString(markdown:)`)
- For code blocks: monospaced font, tinted background, horizontal scroll if
  needed, copy button on long press
- For inline code: monospaced font with subtle background tint
- For headers: larger font sizes, appropriate spacing
- For lists: proper indentation and bullet/number styling
- For links: tappable, open in Safari in-app browser
- For tables: render as styled grids (if SwiftUI supports, otherwise as
  formatted monospaced text)

### 2.2 Message Density Controls

Expand the current "compact mode" into a density slider:

- Spacious: current default, generous padding, large touch targets
- Normal: slightly tighter, good for casual reading
- Dense: minimal padding, smaller fonts, maximum content per screen
- Terminal: monospaced, near-zero padding, terminal-style line spacing

Each theme has a default density but users can override.

### 2.3 Auto-Scroll and Scroll Position

Current auto-scroll jumps to bottom on new messages. Improve:

- Add a "jump to bottom" button when scrolled up
- Preserve scroll position when new messages arrive if user is reading history
- Smooth scroll animation for new messages, instant for initial load
- Add scroll-to-bottom on tap of the nav bar title

### 2.4 Message Selection and Actions

- Long press a message to show context menu: Copy, Copy as Markdown, Share,
  Regenerate (if assistant message), Delete
- Selectable text is already enabled; add explicit copy button for whole message
- For code blocks: dedicated copy button

### 2.5 Conversation Search

- Add search bar in the session view to search within conversation history
- Highlight matching text in results
- Tap result to scroll to that message

---

## Hermes API Feature Inventory

The Hermes API server exposes these endpoints. Here is what exists, what the
app already uses, and what we should wire up for remote control.

### Already Wired and Working

| Endpoint | Method | App Usage | Status |
|----------|--------|-----------|--------|
| /health | GET | Connection test | Working |
| /v1/capabilities | GET | Server info, feature detection | Working |
| /api/sessions | GET | Session list | Working |
| /api/sessions | POST | Create session | Working |
| /api/sessions/{id} | DELETE | Delete session | Working |
| /api/sessions/{id}/messages | GET | Load conversation history | Working |
| /api/sessions/{id}/chat | POST | Non-streaming chat (primary path) | Working |
| /api/sessions/{id}/chat/stream | POST | SSE streaming (code exists, not active) | Parked |
| /v1/skills | GET | Skills list in settings | Working |

### Available But Not Yet Wired

| Endpoint | Method | What It Does | Priority |
|----------|--------|-------------|----------|
| /v1/models | GET | List available models + route aliases | High |
| /v1/toolsets | GET | List toolsets, their tools, enabled state | High |
| /api/sessions/{id} | GET | Full session metadata (tokens, cost, lineage) | Medium |
| /api/sessions/{id} | PATCH | Rename session, set end_reason | High |
| /api/sessions/{id}/fork | POST | Branch a session (like /branch in CLI) | Medium |
| /v1/runs | POST | Submit async agent run (fire and forget) | High |
| /v1/runs/{id} | GET | Check run status | High |
| /v1/runs/{id}/events | GET | SSE stream of run events (tool progress, deltas) | High |
| /v1/runs/{id}/approval | POST | Approve/deny a pending tool execution | High |
| /v1/runs/{id}/stop | POST | Cancel a running agent | High |
| /api/jobs | GET | List cron jobs | Medium |
| /api/jobs | POST | Create cron job (schedule, prompt, skills) | Medium |
| /api/jobs/{id} | GET | Get single cron job | Medium |
| /api/jobs/{id} | PATCH | Update cron job (schedule, prompt, pause/resume) | Medium |
| /api/jobs/{id} | DELETE | Delete cron job | Medium |
| /api/jobs/{id}/pause | POST | Pause cron job | Medium |
| /api/jobs/{id}/resume | POST | Resume cron job | Medium |
| /api/jobs/{id}/run | POST | Manually trigger a cron job now | Medium |
| /v1/chat/completions | POST | OpenAI-compatible chat (alternative to session chat) | Low |
| /v1/responses | POST | OpenAI Responses API compatible | Low |
| /v1/responses/{id} | GET | Get response by ID | Low |
| /v1/responses/{id} | DELETE | Delete response | Low |

### What We Can and Should Control Remotely

Grouped by function, not by endpoint.

**1. Model and Toolset Awareness (High Priority)**
- GET /v1/models: Show which model is active and what aliases are available.
  Lets the user see what they are talking to. If route aliases exist, the user
  could switch models from the phone (send a request to the agent asking it to
  switch, or if a future endpoint supports direct switching, wire that).
- GET /v1/toolsets: Show which toolsets are enabled on the server. The user
  sees what tools the agent has access to (web, terminal, file, browser, etc.).
  This is read-only for now; toolset toggling requires a config change on the
  server, but visibility is valuable.

**2. Session Management (High Priority)**
- PATCH /api/sessions/{id}: Rename sessions from the phone. Long press a
  session, tap Rename, edit inline.
- GET /api/sessions/{id}: Show session metadata: token counts, estimated cost,
  tool call count, lineage (parent session if forked). Add a session detail
  view or expand the session row.
- POST /api/sessions/{id}/fork: Fork a session from the phone. Creates a new
  session with the same conversation history. Useful for branching a
  conversation without losing the original.

**3. Async Runs (High Priority)**
- POST /v1/runs: Submit a task that runs in the background on the server.
  Unlike session chat (which blocks until the response is ready), runs return
  immediately with a run_id. The user can submit a long task, put the phone
  away, and check back later.
- GET /v1/runs/{id}: Check if a run is still going, completed, or failed.
- GET /v1/runs/{id}/events: Stream events from a run in progress. Shows tool
  progress, text deltas, and completion. This is the "live activity" view for
  background tasks.
- POST /v1/runs/{id}/stop: Cancel a run that is taking too long or went in the
  wrong direction. The stop button already exists in the UI for streaming; wire
  it to this endpoint for async runs.
- POST /v1/runs/{id}/approval: When the agent needs permission to run a
  command, the app shows the approval card. User taps Allow Once, Allow Session,
  or Deny. The approval card UI already exists in GlassApprovalCard; it needs
  to be fed real data from run events.

**4. Cron Job Management (Medium Priority)**
- GET /api/jobs: List all scheduled cron jobs. Shows schedule, prompt, last
  run, next run, status. The user can see what their agent is doing on a
  schedule.
- POST /api/jobs: Create a new cron job from the phone. User enters a prompt,
  picks a schedule (every 30m, daily at 9am, etc.), optionally selects skills,
  and saves. The agent will run that prompt on schedule.
- PATCH /api/jobs/{id}: Edit a cron job's schedule or prompt.
- POST /api/jobs/{id}/pause and /resume: Toggle a cron job on/off without
  deleting it.
- POST /api/jobs/{id}/run: Trigger a cron job immediately (manual fire).
- DELETE /api/jobs/{id}: Remove a cron job.

This turns the phone into a remote control for the agent's scheduled tasks.
The user can see, create, edit, pause, and trigger jobs without opening a
terminal.

**5. Streaming Chat (Re-enabled, High Priority)**
- POST /api/sessions/{id}/chat/stream: The SSE parser already exists in
  HermesAPIClient. Bring it back as the primary path with the non-streaming
  endpoint as fallback. The timeout fix (600s request, 1800s resource) applies
  to both paths now. Streaming gives token-by-token feedback, tool progress
  events, and a better user experience for long responses.

**6. Session Chat with System Messages (Available Now)**
- The chat endpoint accepts an optional system_message field. The app could
  let users set per-session instructions (e.g., "respond in Spanish" or "be
  concise") that get sent as the system_message. Add a session settings sheet
  with a text field for custom instructions.

---

## Phase 3: Feature Expansion

Goal: Add the features that make the app a real Hermes client, not just a chat
window. Priorities are based on the API inventory above.

### 3.1 Streaming Chat (Re-enabled)

The non-streaming endpoint works but has no live feedback. Bring back streaming
with proper handling:

- Use the hardened SSE parser already in `HermesAPIClient.swift`
- Show token-by-token streaming with theme-appropriate cursor
- Show tool progress events as they arrive
- Handle connection drops gracefully (auto-retry once, then show error)
- Allow user to stop streaming mid-response (already wired but needs testing)
- Keep non-streaming as automatic fallback if SSE fails within 3 seconds

### 3.2 Voice Input

The app already declares microphone and speech recognition permissions in
Info.plist. Wire them up:

- Microphone button in the input bar (currently disabled placeholder)
- Record audio, transcribe locally or via Hermes STT endpoint
- Insert transcribed text into the input field
- Hold-to-talk or tap-to-toggle recording
- Visual feedback: waveform or pulsing indicator while recording

### 3.3 Image Attachment and Vision

The app declares camera usage. Add:

- Camera button (currently disabled) to open camera or photo picker
- Send image to Hermes with the message (multipart upload or base64 inline)
- Show image thumbnail in the user message bubble
- Support pasting images from clipboard

### 3.4 Session Management

Expand the session picker:

- Search sessions by title
- Sort by last active, title, message count
- Show last message preview in each session row
- Swipe to delete
- Pull to refresh (already present)
- Session fork (if API supports it, create new session from current point)
- Rename sessions inline

### 3.5 Skills Browser

The settings view shows a flat list of skills. Improve:

- Group skills by category
- Search skills by name or description
- Tap a skill to see full description
- Load a skill into the active session (send `/skill <name>` as a message)
- Show skill categories with icons

### 3.6 Tool Approvals (Full)

The `GlassApprovalCard` exists but needs real wiring:

- Poll for pending approvals or receive via SSE
- Show approval card inline in chat when a tool needs approval
- Send approval response back to Hermes
- Support "allow once", "allow session", "deny"
- Show the full command that needs approval
- Add "always allow this tool" option (if API supports)

### 3.7 Model and Provider Switching

- Show current model in settings (already shown in server info)
- Add ability to switch model from the app (if API supports)
- Show provider info
- Quick model switch from chat screen (long press nav bar or dedicated button)

### 3.8 Push Notifications

- Register for push notifications
- Notify when a long-running task completes while app is backgrounded
- Notify when approval is needed
- Notify when a new session message arrives from another platform

### 3.9 Multi-Server Profiles

- Support multiple Hermes server connections (home, work, etc.)
- Quick switch between servers from the connection screen
- Per-server session lists and settings
- Stored in Keychain, switchable from settings

### 3.10 Widget Support

- Lock screen widget showing latest Hermes message
- Home screen widget showing session count and last active
- Interactive widget to quick-send a message

---

## Phase 4: Polish and Platform Integration

### 4.1 Haptics

- Light haptic on send
- Success haptic on response received
- Warning haptic on approval needed
- Error haptic on failure

### 4.2 Keyboard Shortcuts (iPad)

- Cmd+Enter to send
- Cmd+K to search sessions
- Cmd+, to open settings
- Cmd+N for new session
- Arrow keys to navigate message history

### 4.3 Context Menu Integration

- Long press app icon for quick actions: New Chat, Last Session, Settings
- Share extension: share text to Hermes as a new message

### 4.4 iPad and Landscape

- Current target includes iPad (TARGETED_DEVICE_FAMILY: "1,2")
- Add split view: session list on left, chat on right (iPad)
- Landscape phone: wider bubbles, optional two-column on Pro Max

### 4.5 Dynamic Type and Accessibility

- Full Dynamic Type support across all themes
- VoiceOver labels for all interactive elements
- Reduce motion support (disable animations, blinking cursors)
- High contrast mode
- Reduce transparency support (for glass themes)

---

## Build and Version Plan

| Version | Build | Content |
|---------|-------|---------|
| 1.0.3 | 4 | Current: working non-streaming chat (DO NOT BREAK) |
| 1.1.0 | 5+ | Phase 1: Theme system with 3 presets |
| 1.2.0 | TBD | Phase 2: Markdown rendering, density controls, search |
| 1.3.0 | TBD | Phase 3.1-3.4: Streaming, voice, images, session mgmt |
| 1.4.0 | TBD | Phase 3.5-3.8: Skills, approvals, model switch, push |
| 1.5.0 | TBD | Phase 3.9-3.10: Multi-server, widgets |
| 2.0.0 | TBD | Phase 4: Full polish, iPad, accessibility |

---

## Rules for This Branch

1. Never break the working chat. Test send/receive after every change.
2. Keep the Hermes (Liquid Glass) theme as default and always functional.
3. New themes are additive; they do not replace existing styling until
   fully tested.
4. Bump version and build for every installed test build.
5. Commit to `feature/theme-system-and-ui-overhaul`, PR to `Dev_Erick`.
6. No mock data. Test against the real Hermes gateway.
7. No emojis in formal docs, code comments, or commit messages.