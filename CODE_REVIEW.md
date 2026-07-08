# HermesCompanion iOS App — Two-Pass Code Review Report

**Date:** July 8, 2026
**Reviewer:** ct-review-architect skill (automated)
**Repository:** /Users/erick/repos/HermesCompanion
**Files reviewed:** 21 Swift source files + project.yml + Info.plist + .gitignore (10,555 lines total)
**Mode:** Read-only audit (no files modified)

---

## Summary

| Severity | Count |
|----------|-------|
| Critical | 2 |
| High | 5 |
| Medium | 8 |
| Low | 4 |
| Cross-layer | 10 |
| **Total** | **29** |

---

## Phase 1: Primary Audit Findings (Layer-by-Layer)

### CRITICAL

**C1. TLS Private Keys Committed to Git**
- **WHAT**: Four PEM files including private keys are tracked in git: `certs/100.x.x.x+2-key.pem`, `certs/100.x.x.x+2.pem`, `certs/cert.pem`, `certs/key.pem`. These are TLS certificates for a Tailscale node (IP 100.x.x.x).
- **HOW**: `certs/` directory — `git ls-files` confirms all 4 files are tracked. `.gitignore` does not exclude `certs/`.
- **WHY**: Anyone with repository access obtains the private keys for the user's Tailscale-adjacent TLS certificates. This is a severe credential exposure that could allow MITM or impersonation of the Hermes server.
- **SEVERITY**: **Critical**

**C2. Thinking Safety Timer Never Started — Voice Can Hang Forever**
- **WHAT**: `VoiceConversationManager.scheduleThinkingSafetyTimer()` (line 677) is defined but **never called from anywhere**. The `thinkingSafetyTimer` property is only invalidated, never set. In `finalizeTranscription`, `isThinking = true` is set (lines 628, 644, 653) but the 90-second safety timer that's supposed to prevent the user from being stuck in thinking mode is never started.
- **HOW**: `Sources/VoiceConversationManager.swift` — `scheduleThinkingSafetyTimer()` at line 677, `invalidateThinkingSafetyTimer()` at 690. Search confirms zero call sites for `scheduleThinkingTimer`.
- **WHY**: If the Hermes server stops responding mid-stream (network drop, gateway error), the user is stuck in "THINKING..." indefinitely. In local mode, there's no timeout at all. The ChatView's 60s VoiceTimeoutManager partially covers the remote path, but local mode and any non-ChatView entry point are completely unprotected.
- **SEVERITY**: **Critical**

### HIGH

**H1. Reconnect Retry Loop Has No Backoff or Max Retries**
- **WHAT**: `AppStore.reconnectIfNeeded()` (line 918) schedules a blind 3-second retry via a detached `Task` that calls `reconnectIfNeeded()` again. There's no exponential backoff, no max retry count, and no cancellation if the app goes to background or the user disconnects.
- **HOW**: `Sources/AppStore.swift` lines 918–925
- **WHY**: If the server stays down, this creates an infinite loop of health check attempts every 3 seconds, consuming battery and network resources. On Tailscale (which can take 30+ seconds to reconnect), this is particularly wasteful.
- **SEVERITY**: **High**

**H2. VoiceTranscriber: `removeTap` Called Without Guard — Potential Crash**
- **WHAT**: `VoiceTranscriber.stopTranscription()` calls `audioEngine.inputNode.removeTap(onBus: 0)` unconditionally (only gated by `audioEngine.isRunning`). Unlike `VoiceConversationManager` which tracks `hasInstalledInputTap`, `VoiceTranscriber` has no such guard.
- **HOW**: `Sources/VoiceTranscriber.swift` line 128
- **WHY**: If `stopTranscription()` is called when the tap was never installed (e.g., `startTranscription` failed early), calling `removeTap` on a node without a tap throws an uncatchable Objective-C exception that crashes the app.
- **SEVERITY**: **High**

**H3. `streamRunEvents` SSE Parser Is Less Robust Than `streamChat`**
- **WHAT**: The `streamRunEvents` parser (line 356) doesn't handle CRLF line endings, doesn't handle SSE comment lines (`:` prefix), doesn't handle multiple `data:` lines per frame (overwrites instead of concatenating), and doesn't flush unterminated frames at stream end. The `streamChat` parser was patched to handle all of these.
- **HOW**: `Sources/HermesAPIClient.swift` lines 356–385 vs. 248–306
- **WHY**: If run events use CRLF endings or have keepalive comments, frames will be misparsed or dropped. Run events (used for async agent execution and tool approvals) would silently fail to reach the UI.
- **SEVERITY**: **High**

**H4. Version Mismatch Between `project.yml` and `Info.plist`**
- **WHAT**: `project.yml` specifies `MARKETING_VERSION: "1.8.23"` and `CURRENT_PROJECT_VERSION: 49`, but `Info.plist` has `1.8.24` and `59`. The git log shows v1.8.24 (59) as latest.
- **HOW**: `project.yml` lines 43–44 vs `Sources/Info.plist` lines 20–22
- **WHY**: If the Xcode project is regenerated via `xcodegen` (which the `.gitignore` implies — `HermesCompanion.xcodeproj` is ignored), the version will regress to 1.8.23 (49), causing confusion and potential TestFlight rejection.
- **SEVERITY**: **High**

**H5. `NSAllowsArbitraryLoads: true` — ATS Completely Disabled**
- **WHAT**: App Transport Security is fully disabled in both `project.yml` and `Info.plist`.
- **HOW**: `project.yml` line 39, `Sources/Info.plist` lines 23–27
- **WHY**: While needed for HTTP Tailscale IPs, disabling ATS entirely allows any HTTP traffic, including accidental non-Tailscale connections. Should use `NSExceptionDomains` with minimum TLS version requirements.
- **SEVERITY**: **High**

### MEDIUM

**M1. `isHermesConnected` Defaults to `true` Before Connection Established**
- **WHAT**: `VoiceConversationManager.isHermesConnected` is initialized to `true` (line 158). On first launch before any connection, the voice manager defaults to remote mode.
- **HOW**: `Sources/VoiceConversationManager.swift` line 158
- **WHY**: `ChatView.onAppear` sets it correctly, but there's a window where the default is wrong. If voice mode is accessed before `onAppear` fires, it would attempt remote mode with no server.
- **SEVERITY**: **Medium**

**M2. `refreshDefaultMode` Has a No-Op Network Check Branch**
- **WHAT**: The `else` branch (line 167) does a network connectivity check but sets `conversationMode = .remote` in both the `isConnected == true` and `isConnected == false` paths. The network check result is irrelevant.
- **HOW**: `Sources/VoiceConversationManager.swift` lines 167–181
- **WHY**: Dead logic that wastes a network check. Misleading to maintainers.
- **SEVERITY**: **Medium**

**M3. GlassBubble Shows Current Time Instead of Message Timestamp**
- **WHAT**: When `showTimestamp` is true, `Text(Date(), style: .time)` is used instead of the message's actual timestamp.
- **HOW**: `Sources/GlassTheme.swift` line 88
- **WHY**: Every message shows the time it was rendered, not when it was sent/received. Users see misleading timestamps.
- **SEVERITY**: **Medium**

**M4. `hasNetworkConnectivity` NWPathMonitor Can Leak**
- **WHAT**: The `NWPathMonitor` is only cancelled in the `pathUpdateHandler`. If the handler never fires (edge case), the monitor runs forever, leaking memory.
- **HOW**: `Sources/VoiceConversationManager.swift` lines 979–991
- **WHY**: Memory leak in rare edge cases.
- **SEVERITY**: **Medium**

**M5. `failRemoteTurn` Speaks Error Even After Voice Page Closed**
- **WHAT**: `failRemoteTurn` calls `speakResponse(message)` (line 340) **before** the `guard isConversing` check (line 342). If the user closed the voice page while a network request was in flight, the error message is spoken aloud even though the conversation is no longer active.
- **HOW**: `Sources/VoiceConversationManager.swift` lines 332–353
- **WHY**: User hears an unexpected voice prompt after closing the voice page.
- **SEVERITY**: **Medium**

**M6. Extensive `print()` Statements in Production Code**
- **WHAT**: Multiple `print()` calls throughout `VoiceConversationManager` (lines 306, 646, 655, 749–755, 820–824, 873–878) and `ChatView` (lines 657, 335, 342). Should use `FileLogger` or `#if DEBUG`.
- **HOW**: Various files
- **WHY**: Console noise in production, potential PII exposure in device logs.
- **SEVERITY**: **Medium**

**M7. VoiceConversationPage MUTE and LOCAL Buttons Are No-Ops**
- **WHAT**: The MUTE button (line 264) has an empty closure. The LOCAL button (line 313) has an empty closure. Both are visible UI elements that do nothing.
- **HOW**: `Sources/VoiceConversationPage.swift` lines 264, 313
- **WHY**: User confusion — tapping buttons with no effect.
- **SEVERITY**: **Medium**

**M8. ConnectionSetupView "Done" Button Is a No-Op When Editing**
- **WHAT**: When `initialConfig != nil`, the toolbar "Done" button has an empty closure.
- **HOW**: `Sources/ConnectionSetupView.swift` lines 96–99
- **WHY**: User can't dismiss the edit sheet via the Done button.
- **SEVERITY**: **Medium**

### LOW

**L1. FileLogger Has No Log Rotation**
- **WHAT**: `hermes-companion.log` grows indefinitely with no size cap or rotation.
- **HOW**: `Sources/Models.swift` lines 7–42
- **SEVERITY**: **Low**

**L2. `AnyCodable.encode` Loses Unknown Types**
- **WHAT**: The `default` case in `encode` (line 391) encodes nil for unrecognized types, silently losing data.
- **HOW**: `Sources/Models.swift` line 391
- **SEVERITY**: **Low**

**L3. `KeychainManager` Missing `kSecAttrAccessGroup`**
- **WHAT**: No access group set, preventing future app extension keychain sharing.
- **HOW**: `Sources/KeychainManager.swift` line 92–104
- **SEVERITY**: **Low**

**L4. `project.yml` Has Empty `DEVELOPMENT_TEAM`**
- **WHAT**: `DEVELOPMENT_TEAM: ""` means the project won't sign without manual configuration.
- **HOW**: `project.yml` line 45
- **SEVERITY**: **Low** (intentional for open-source, but worth noting)

---

## Phase 2: Cross-Layer Pass

### Race Conditions

**X1. Early TTS Monitor + Voice Timeout: Dual Watchers on Same State**
- `ChatView.handleVoiceTranscription` starts two concurrent tasks: a `VoiceTimeoutManager` 60s timeout and a monitor task polling `store.streamingText` every 100ms. If the timeout fires and calls `failRemoteTurn`, `isThinking` becomes false, and the monitor's while loop exits. This works but is fragile — the two watchers aren't coordinated and both touch voice manager state.

**X2. `store.sendMessage` Completes After Voice Page Dismissed**
- If the user closes the VoiceConversationPage while a stream is in flight, `VoiceConversationPage.onDisappear` calls `stopConversation()`, which sets `isConversing = false`. But `store.sendMessage` continues to completion, and `completeRemoteTurn`/`failRemoteTurn` will still fire. `failRemoteTurn` speaks the error **before** the `isConversing` guard (M5). `completeRemoteTurn` checks `isSpeaking` but doesn't check `isConversing` before calling `speakResponse`. The `speakResponse` method does check `isConversing` (line 748) and returns early, so the TTS won't actually play. But `spokenResponse` is still set, causing stale UI.

### Memory Leaks

**X3. NWPathMonitor Leak** — See M4. The `NWPathMonitor` in `hasNetworkConnectivity()` has no timeout. If `pathUpdateHandler` never fires, the monitor and its queue persist forever.

**X4. All Timers Properly Cleaned Up (Except `thinkingSafetyTimer`)** — `levelTimer`, `silenceTimer`, `bargeInCheckTimer` are all properly invalidated in `stopListening()` / `stopConversation()`. `thinkingSafetyTimer` is invalidated but never started (C2), so no leak, just dead code.

### State Machine Gaps in Voice Lifecycle

**X5. No "Disconnected" State in Voice Conversation**
- The voice lifecycle has: idle -> listening -> finalizing -> thinking -> speaking -> listening (loop). There's no "disconnected" state. If the network drops during thinking, the only recovery is the ChatView's 60s timeout (remote mode) or nothing (local mode). The `thinkingSafetyTimer` was intended to handle this but is never started (C2).

**X6. `isFinalizing` Flag Can Get Stuck**
- If `finalizeTranscription` is called and `isFinalizing = true` is set (line 622), but then the callback (`onTranscriptionComplete`) throws or the network fails before `completeRemoteTurn` is called, `isFinalizing` stays true. The next `finalizeTranscription` call will hit the `guard !isFinalizing` check (line 614) and just call `stopListening()` without resuming the conversation. The user has to manually tap to resume.

### Dead Code from Iterative Development

**X7. Dead Code Inventory:**
- `VoiceConversationOverlay` (GlassTheme.swift line 876) — replaced by VoiceConversationPage, never referenced
- `micButton` (GlassTheme.swift line 763) — replaced by inline mic button, never referenced
- `startVoiceConversation` (GlassTheme.swift line 816) — never called
- `transcriptionCards` (VoiceConversationPage.swift line 222) — replaced by `transcriptionDisplay`, never referenced
- `GlassConnectionCard` (GlassTheme.swift line 1127) — appears unused
- `scheduleThinkingSafetyTimer` (VoiceConversationManager.swift line 677) — never called
- The `else` branch network check in `refreshDefaultMode` (M2)
- `VoiceTimeoutManager` — still used but the comment says "Task.sleep cancellation is unreliable" — this was a workaround that's now the primary timeout mechanism

### Mismatched Assumptions

**X8. VoiceConversationPage Forces `.remote` Mode, Ignores User Preference**
- `VoiceConversationPage.onAppear` (line 119) unconditionally sets `conversationMode = .remote`, and `startVoiceConversationIfNeeded` (line 339) also forces `.remote`. If the user selected local or premium mode, it's overridden.

**X9. ChatView and VoiceConversationPage Share `voiceConversation` Object**
- ChatView creates `@StateObject private var voiceConversation = VoiceConversationManager()` and passes it to both GlassInputBar and VoiceConversationPage. When the full-screen cover is dismissed, `VoiceConversationPage.onDisappear` calls `stopConversation()`, which resets all state. But the GlassInputBar's live conversation indicator (line 488) checks `voiceConversation.isConversing`, which is now false. This is correct behavior, but the shared object means state changes from one view affect the other immediately.

**X10. `store.sendMessage` with `skipPostReload: true` Skips Session Refresh**
- Voice mode skips the post-stream message reload (line 643). This means `store.messages` doesn't get the server-authoritative version of the assistant response. If the streamed text differs from the server's final version (e.g., the server applied post-processing), the chat view shows the streamed version, not the canonical one. The messages will only be corrected when the user switches sessions or the app reconnects.

---

## Recommended Fix Priority List

| Priority | Finding | Fix |
|----------|---------|-----|
| 1 | C1: TLS private keys in git | Remove certs from git history (`git filter-repo`), add `certs/` to `.gitignore`, rotate all exposed certificates |
| 2 | C2: Thinking safety timer never started | Call `scheduleThinkingSafetyTimer()` after every `isThinking = true` in `finalizeTranscription` |
| 3 | H2: VoiceTranscriber crash on removeTap | Add `hasInstalledInputTap` guard like VoiceConversationManager |
| 4 | H1: Reconnect retry has no backoff | Add exponential backoff (3s -> 6s -> 12s -> 30s) and max retry count (10) |
| 5 | H3: streamRunEvents parser inconsistencies | Port the robust parser from streamChat (CRLF handling, comment lines, multi-data, final flush) |
| 6 | H4: Version mismatch | Sync project.yml to 1.8.24 (59) or use `$(MARKETING_VERSION)` in Info.plist |
| 7 | H5: ATS fully disabled | Use `NSExceptionDomains` instead of `NSAllowsArbitraryLoads` |
| 8 | M5: failRemoteTurn speaks after close | Move `speakResponse` after the `guard isConversing` check |
| 9 | M3: Wrong timestamp in GlassBubble | Pass message timestamp to GlassBubble instead of using `Date()` |
| 10 | M7: No-op MUTE/LOCAL buttons | Wire up or remove the buttons |
| 11 | X7: Dead code cleanup | Remove VoiceConversationOverlay, micButton, startVoiceConversation, transcriptionCards, GlassConnectionCard |
| 12 | M6: print() in production | Replace with FileLogger or `#if DEBUG print() #endif` |
| 13 | M8: Done button no-op | Add `dismiss()` to the Done button closure |
| 14 | X3: NWPathMonitor leak | Add a timeout task that cancels the monitor after 5 seconds |
| 15 | L1: FileLogger no rotation | Add max file size check and truncate/rotate |

---

## Architecture Assessment

**Biggest architectural risk**: The voice pipeline has multiple uncoordinated safety nets (ChatView's 60s timeout, the never-started thinking timer, the monitor task) that work by accident rather than design. A dedicated voice state machine with explicit transitions would eliminate the race conditions and stuck-state possibilities.

**Strengths**:
- Clean separation between AppStore (state), ChatView (UI), VoiceConversationManager (voice logic), and HermesAPIClient (network)
- Proper use of SwiftUI patterns: @StateObject, @Published, @EnvironmentObject
- Good use of SSE streaming for real-time chat
- Solid multi-server Keychain management
- Theme system is well-architected with protocol-based themes

**Weaknesses**:
- Voice pipeline state is spread across 3 files (ChatView, VoiceConversationManager, VoiceConversationPage) with no single source of truth
- Timers and audio engines are managed manually without a lifecycle coordinator
- Error recovery in the voice path is ad-hoc — each failure point has its own recovery logic
- No test coverage for any of the voice or streaming code

---

*Review generated by ct-review-architect skill on July 8, 2026. No files were modified during this audit.*
