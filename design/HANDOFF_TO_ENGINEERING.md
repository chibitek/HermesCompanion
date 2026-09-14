# Hermes Companion — Prototype → Code Handoff

This document lets another engineer (or AI session) wire the interactive prototype
(`Hermes Companion.dc.html`) to the real iOS app. It describes every screen, its
components, states, data bindings, and interactions. The prototype is a **visual +
interaction reference** — not production code. Follow the app's existing SwiftUI/UIKit
architecture; use this as the spec for layout, styling, and behavior.

---

## 1. Design tokens

Pull these into your theme layer (e.g. a `Theme` enum / asset catalog). All screens use them.

| Token | Value | Usage |
|---|---|---|
| `brand/teal` | `#00B398` | Primary accent, user bubbles, connected status, active model |
| `brand/teal-bright` | `#00D4B3` | Links, inline highlights, "Done" buttons |
| `brand/amber` | `#F2A900` | Approval / warning CTAs |
| `brand/danger` | `#CF4520` | Destructive rows (Remove server, Disconnect) |
| `bg/base` | `#0A0E16` | App background (deep navy) |
| `bg/surface` | `#162032` | Screen surface (chat) |
| `bg/surface-alt` | `#0E1522` | Sessions / Settings surface |
| `bg/card` | `rgba(30,42,64,.6)` | Settings/message cards (glass) |
| `text/primary` | `#F2F6FC` | Titles |
| `text/body` | `#DBE4F1` | Message body |
| `text/secondary` | `#7E8EA6` | Metadata, captions |
| `text/muted` | `#5C6B84` | Timestamps, placeholders |
| `matrix/green` | `#00FF41` | Voice screen text/glow |

**Type:** Titles & UI = Hanken Grotesk (fallback SF Pro / system). Monospace (model
names, tool calls, timestamps, terminal/voice) = JetBrains Mono (fallback SF Mono).

**Glass surfaces:** `background: rgba(30,42,64,.6–.85)` + `backdrop-filter: blur(20px)`
+ `1px` border `rgba(255,255,255,.07)`. In SwiftUI use `.ultraThinMaterial`/`.regularMaterial`
tinted, or `UIVisualEffectView` with a dark blur + teal-tinted overlay.

**Radii:** cards 16–18px, message bubbles 20px (6px on the "tail" corner), pills 20–24px,
icon buttons 11px.

---

## 2. Navigation model

Four screens, single-stack. Prototype uses cross-fade + scale; on iOS use the natural
presentations noted below.

```
Chat (root)
 ├─ tap "‹" (top-left)        → Sessions   (present as .sheet or push)
 ├─ tap gear (top-right)      → Settings   (present as .sheet)
 └─ tap waveform (input bar)  → Voice      (present fullScreenCover)

Sessions ─ tap "Done" or a session row → Chat
Settings ─ tap "Done"                  → Chat
Voice    ─ tap "✕" or END               → Chat
```

State in prototype: `screen ∈ {chat, voice, sessions, settings}`. In the app this maps to
NavigationStack path + sheet/cover bindings.

---

## 3. Screen: Chat (main)

Root screen. Streaming agent conversation with tool calls and approvals.

**Nav bar (glass, sticky)**
- Left `‹` button → opens Sessions.
- Center: session title (`Server log cleanup`), and a status line: teal dot +
  `Hermes-4-405B · connected`. Bind dot color to connection state
  (connected=teal, connecting=amber pulse, error=danger).
- Right gear → opens Settings.

**Message list** (bottom-anchored, auto-scroll to newest)
- **Date separator**: centered mono caption (`TODAY · 9:38 AM`).
- **Assistant bubble**: left-aligned, `bg/card`, radius `20 20 20 6`. Supports inline
  bold accents in `brand/teal-bright`.
- **User bubble**: right-aligned, teal gradient fill, dark text, radius `20 20 6 20`.
- **Tool-call chips** (grouped, left-aligned):
  - *Running*: spinner (teal) + tool name (mono, teal) + args (mono, muted). Border teal.
  - *Done*: teal `✓` + tool name + short result. Border neutral.
  - Bind to the agent's tool-execution stream. Each chip = one `tool_use`/`tool_result` pair.
- **Approval prompt** (amber card): shown when the agent requests a gated action.
  - Header `⚠ APPROVAL REQUIRED` (amber, mono).
  - The command in a mono code block.
  - `Approve` (amber gradient) / `Deny` (neutral) buttons → resolve the pending
    approval and continue/stop the run.
- **Streaming assistant**: same as assistant bubble, with a blinking teal caret block at
  the end while tokens stream. Remove caret on completion.

**Input bar** (sticky bottom, glass)
- Model pill (above input): teal dot + `Hermes-4-405B` + `▾` → opens model picker.
- `+` (attachments), text field (`Message Hermes…`), mic glyph, and the teal **waveform**
  button → opens Voice.

**Data:** messages `[{role, content, toolCalls?, approval?, streaming?}]`; connection
status; active model. Wire to the existing chat/session store.

---

## 4. Screen: Voice Conversation (Matrix theme)

Full-screen cover. Real-time voice mode with the "Matrix" appearance preset.

**Background layers (bottom→top)**
1. `matrix-rain` — a `<canvas>` of falling katakana/alphanumeric glyphs in green, with a
   bright leading glyph. On iOS: a `CADisplayLink`/`TimelineView` `Canvas` renderer, or a
   `SpriteKit`/Metal layer. Runs only while the screen is active; stop on dismiss.
2. Scanlines — repeating 1px dark horizontal lines at low opacity + slow flicker.
3. Vignette + CRT glow — radial green glow center, darkening to edges.

**Content**
- Top bar: `◉ VOICE_MODE` (green, mono, subtle glitch animation) + `✕` close.
- Transcription (centered, mono): `> YOU` line (dim green) and `> HERMES` line (bright
  green with glow) + blinking caret while the agent speaks/streams. Bind to STT (user)
  and the agent's streamed reply (assistant).
- **Audio waveform**: row of vertical bars animating with amplitude. In prototype it's a
  synthetic sine+random envelope; in the app drive bar heights from the live mic/output
  audio level (e.g. `AVAudioEngine` tap RMS, or TTS playback level).
- Controls: `MUTE` (toggle mic), center **END** (green, ends the voice session → back to
  Chat), `LOCAL` (toggle local/remote or device mode).

**Notes:** The Matrix look is one of several appearance presets (see Settings →
Appearance). Structure the theme so Neon / Amber / Blue-Hacker swap the palette + rain
glyphs without changing layout.

---

## 5. Screen: Sessions

Session history list. Present as sheet/push from Chat's `‹`.

**Header (sticky, glass):** `Done` (teal, left) → Chat; `Sessions` title; right actions
`+` (new session) and a sort/import glyph.

**List rows** — each session:
- Title (e.g. `Hermes Gateway Configuration And Restart #34`).
- Subtype tag in mono teal: `cron` / `tui` / `api_server` (the session's origin).
- Metadata: `{messageCount} messages · {duration}`.
- The **active/selected** session is highlighted: teal-tinted card, teal border, trailing
  teal `✓`. Bind to the currently open session id.
- Tap a row → open that session in Chat.
- (Not built, recommended) long-press → context menu: Rename / Fork / Delete.

**Bottom:** search bar (`Search sessions`) filtering the list by title.

**Data:** `[{id, title, subtype, messageCount, duration, updatedAt, isActive}]` from the
sessions store; sorted by recency.

---

## 6. Screen: Settings

Grouped settings list. Present as sheet from Chat's gear. `Done` (teal, top-right) → Chat.

Sections (each a grouped card, `bg/card`):

1. **Server**
   - `Server` picker → current server name (`Hermes on Max`), teal value + `⇅`.
   - Server URL row with globe icon (`http://100.x.x.x:8642`), mono.
   - `Remove This Server` (danger).
2. **Provider**
   - `Provider` picker (`Nous`) + caption explaining it's synced from the connected server.
3. **Model**
   - `Active Model` picker; caption: models refresh from the server per provider.
4. **Reasoning**
   - `Thinking` picker (`Off`); caption: local preference only until server honors it.
5. **Capabilities**
   - `Skills API` toggle (on = teal check).
   - `Skills` (count `238`) `›`, `Toolsets` (`13/25`) `›` → detail lists.
   - `Appearance` (`Cyberpunk`) `›` → theme/preset picker (this is where Matrix/Neon/etc live).
   - `Voice` (`Yuna (Premium)`) `›` → voice picker.
   - `Disconnect` (danger).
6. **About**
   - `Version` (`1.8.21 (37)`), `Hermes Docs ↗`, `GitHub ↗` (external links).

**Pickers:** every `⇅` row is a picker/menu. Values shown are current selections; wire to
the settings store. `›` rows push detail screens (not built in the prototype — build per
the app's existing patterns).

---

## 7. Interaction states to implement (not fully shown in prototype)

- Connection lifecycle: connecting spinner, error banner + retry, reconnect.
- Empty states: no sessions, empty session (`0 messages`).
- Tool-call error state (red chip).
- Approval timeout / auto-deny.
- Voice: permission prompt (mic), listening vs speaking vs idle, connection drop.
- Model picker loading (`No models for {provider}` when list is empty).

---

## 8. Where to look in the prototype

`Hermes Companion.dc.html` — single file. The template holds four screen blocks
(Chat, Voice, Sessions, Settings) inside one iPhone frame; the logic class handles screen
switching, the Matrix rain canvas, and the waveform animation. Copy exact colors, spacing,
radii, and copy text from there — they are the source of truth for visual details.
