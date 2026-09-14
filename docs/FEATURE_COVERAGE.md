# Hermes Companion feature coverage

This record separates implemented surfaces from verified behavior. The original
feature extraction document is a historical roadmap, not evidence of complete
Hermes parity. The current delivered baseline is Companion 1.8.84 (181), native
Hermes 0.21.2 with six compatibility patches, and Companion bridge 0.1.10.

## Current evidence and remaining acceptance

| Requirement | Implementation and evidence | Remaining proof or work |
| --- | --- | --- |
| Two-way chat and streamed text | AppStore, native session APIs; isolated iOS checks cover independent clients, remote history/rename, structured acknowledgements and text fidelity | Physical network transitions, long-running context and latency investigation |
| Response status and recovery | Health, stream activity, watchdog, durable status and replay; controller regression covers same-run reattach without freezing | Physical app suspension, network loss and recovery |
| Steering and approvals | Native run controls and capability gates; live steering verifies consumed or recoverable guidance; contract tests enforce approval identity | Real pending approval flow on an isolated gateway |
| Reasoning and model selection | Per-turn reasoning preserves conversation options; native tests and independent-client live check | Provider-specific reasoning support is not universal |
| Saved servers and session management | Test/switch/delete servers; session history, rename, pin, archive, fork and confirmed deletion | Full physical workflow and accessibility checks |
| Projects | Native profile-scoped project RPC through bridge; bridge tests cover native writes and ownership. New real iOS lifecycle check covers both clients, live invalidation, folder links, archive/restore, active selection and deletion | Physical rendered workflow still requires confirmation |
| Kanban | Boards, task edits, comments, hierarchy, results and attachments; board lifecycle has real iOS live coverage | Full real task/comment/attachment lifecycle and desktop invalidation |
| Bots and profiles | Canonical history, profile ownership checks and capability-aware chat access | Installed gateway does not establish every profile's chat transport; preserve profile authorization |
| Scheduled jobs | Two-client live create/edit/pause/resume/run admission/delete; workspace invalidation plus periodic fallback update the cached list; see [JOB_SYNC.md](JOB_SYNC.md) | Scheduler execution/delivery and native capability coherence (#65), physical rendered workflow |
| Skills, toolsets and artifacts | API client and native UI surfaces exist | Verify every currently enabled operation against native contracts and live behavior |
| Voice and audio | Typed-chat ownership repairs and automatic wake suppression have regression coverage | Physical microphone, music and Bluetooth continuity (#53) |
| Broader Hermes features | Historical extraction lists files, Git, analytics, MCP, profile configuration, session correction and subagent surfaces | These require a fresh native-to-iOS contract inventory and implementation; full parity is not established |
| Delivery | Build 181 installed by device inventory, internal TestFlight Testing, Waiting for Review with manual release | TestFlight invitation acceptance, unlocked-device visual tests, reviewer gateway access and screenshot verification |

## Project lifecycle verification

Use two independent iOS API clients against the isolated native gateway and real
bridge. Create a project with actual disposable server folders. Confirm each
client reads the other's edits, and the app's workspace revision changes after
remote writes. Verify primary-folder changes, archive/restore, active-project
selection and the active-project deletion guard. Clear selection and delete only
the owned project. The runner must fail if project records or active selection
remain, or if linked server files were deleted. No production data is involved.

This fills a coverage gap without changing the shipped app. It does not treat
API success as physical UI acceptance or hide features that remain unfinished.

The new check passed in 3.06 seconds; the measured lifecycle after creation took
2.90 seconds. All nine live iOS checks passed with zero skipped or failed. The
final canonical snapshot contained zero sessions, zero saved projects and no
active project. Both linked server files retained their exact contents. These
are isolated local-run timings, not production latency guarantees.

The runner now checks an empty project baseline and fails on retained project
records, active selection or removed linked files. Test credentials, temporary
paths and captured metadata remain outside public source. Build 181's app binary
is unchanged; this pass adds verification and documentation only.

## Live capability audit, September 14

The installed native gateway advertises session chat, reasoning, model locks,
run submission/status/events/steering/approval/stop and skills. The bridge reports
version 0.1.10 with project, board and task creation/edit/comment capabilities.
Native `admin_config_rw`, `jobs_admin`, `memory_write_api`, `audio_api` and
`realtime_voice` report false. These fields are evidence of the advertised
contract, not proof of route enforcement. In particular, native source still
mounts scheduled-job write routes despite `jobs_admin: false`; the isolated lifecycle now verifies these writes and run admission. Scheduler
execution, delivery and capability coherence remain open in issue #65.
