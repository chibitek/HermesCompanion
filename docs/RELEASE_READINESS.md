# Development Release Readiness

As of September 11, 2026. This is a verification record, not a release approval
or a claim that the full product goal is complete.

## Installed Versus Unreleased

The last verified phone installation is 1.8.62 build 156, from merged PR 42.
It includes Projects, Bots, Kanban browsing, and canonical Bot history.

Development source through `1eee679` adds project-session history, full Kanban
task details and hierarchy, refreshed Bot details, and session/voice/job fixes.
Those changes have not been installed on the phone or pushed for review.
The development bridge is 0.1.3; updating only the iOS app does not deploy its
new gateway routes. No multi-profile serving configuration change was made.

## Evidence

- 69 iOS unit tests passed on iPhone 17 Pro Simulator, iOS 26.5. Coverage includes
  stale list/history/creation responses, deleted session state, canonical Bot
  ownership, task hierarchy, schedule omission, and the CarPlay callback selector.
- Ten bridge route/domain contract tests passed. No live data was mutated by
  these tests.
- The generic iOS Release build passed with signing disabled. Remaining compiler
  warnings include captured weak references in dormant ElevenLabs code, the
  deprecated screen-size lookup in `GlassBubble`, and a duplicate provider icon
  pattern. This does not verify signing, phone installation, or Swift 6 mode.
- Subsequent bubble-layout work removes that deprecated screen-size lookup.
  Hosting-controller checks cover long user/assistant text at 240- and 700-point
  container widths, verifying bounded width and vertical reflow. These are layout
  measurements, not physical-device screenshots or a complete visual review.
- Direct real-domain reads verified six task details and project history in four
  profiles containing project sessions. This does not establish HTTP deployment
  of the new routes or visual verification of the new iOS screens.
- The two local gateway compatibility patches previously passed 162 focused
  server tests. A live local Qwen turn confirmed its named provider and model;
  the diagnostic session was removed. See `../GatewayPatches/README.md`.
- Local branch inventory contains only `Dev_Erick` and `main`, with one worktree.

## Required Before Release

- Obtain approval to push/open the PR, merge, and install the updated bridge/app.
- Increment the build number and perform a signed device build/install. An
  unsigned Release compilation does not verify signing or installation.
- Verify the new project and Kanban screens on the phone, including long text,
  small fonts, themes, navigation, and refreshing after changes made on the Mac.
- Exercise microphone startup, interruption, stop/restart, speech playback,
  background/foreground recovery, and physical CarPlay disconnect behavior.
- Verify API reachability after a graceful gateway restart. A transient macOS
  port-bind failure was observed; a running service alone is insufficient proof.
- Review credential ownership and configuration before enabling cross-profile
  serving. The live non-default native session routes currently return 404.
- Revalidate hosted/other Hermes endpoints separately; local success is not
  evidence of compatibility with every host.

## Product Gaps

Cross-profile Bot message submission, project mutations, Kanban editing, and full
artifact browsing/download workflows remain unfinished. Project history is
limited by Hermes's hydrated-tree membership and native listing limits. Physical
voice stability and complete desktop feature parity have not been established.
Do not describe this development branch as bug-free or fully synchronized across
every Hermes feature based on the focused tests above.
