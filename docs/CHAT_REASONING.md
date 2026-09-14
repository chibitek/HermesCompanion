# Operational chat reasoning controls

## Problem

The reasoning picker previously saved a preference but never sent it to Hermes.
The native API accepts model_options.reasoning, but replacing model_options can
also replace unrelated options on a persisted conversation lock. A mobile
reasoning choice must not erase settings chosen by another client.

## Contract and implementation

Compatibility patch 6 advertises `session_chat_reasoning`. Native session chat
and streaming accept a top-level `reasoning_effort` string. Omission retains the
conversation configuration; `default` uses the gateway's configured reasoning;
`none` disables reasoning; the existing minimal through ultra effort ladder is
supported. Invalid values produce HTTP 400 with `invalid_reasoning_effort` before
agent execution or runtime-lock writes.

The override merges only reasoning fields into the agent's per-turn options,
after the normal conversation model/provider lock is resolved and persisted.
Other options are preserved, and the override is not written to that lock.
Terminal runtime metadata reports the actual agent's `reasoning` configuration,
filtered to known enabled/effort fields. Provider-specific limits still apply.

Companion sends the selection for text, voice-through-chat and attachment turns.
The picker distinguishes Conversation default, Server default and Off. On older
servers it is disabled with a clear support message; chat keeps its existing
reasoning behavior. Existing empty preferences retain conversation defaults.
Settings show the last response's configuration when the server reports it.

## Verification and delivery

The iOS regression first failed because outgoing attachment chat omitted the
selected effort. The repaired focused test passes. Native regressions first
failed for both chat paths; the repaired native suite passed 165 tests. Coverage
includes propagation, invalid input, unchanged conversation options and filtered
runtime metadata. The full iOS suite passed 170 ordinary tests with eight opt-in checks skipped.
All eight real-gateway checks then passed against the isolated local model with
zero sessions or metadata remaining. The new live check verifies the agent's Off
and Low runtime configurations and restoration of the conversation default on a
later request from a second independent client instance.

Patch 6 passed in an isolated native development worktree. The production source
was fast-forwarded after live health reported zero active work. A graceful restart
completed; the control socket reports the deployed revision and HTTP health and
capability checks passed. A production probe confirmed the actual agent received
Off, and its owned verification conversation was deleted with a matching receipt.

Companion 1.8.83 (180) was archived with matching app/widget versions. Its signed
export passed verification, and physical-device inventory confirms installation.
Launch and visual acceptance of this build remain unverified. Apple processed the
upload and build 180 is Testing in the existing internal group. Invitation
acceptance on the phone remains unverified. Authentication and credential storage
are unchanged.

The older build 179 review submission was withdrawn. Apple confirmed build 180
submitted on September 14 at 2:29 AM Eastern and Waiting for Review, with manual
release selected. This delivery does not establish physical audio acceptance or
complete gateway feature parity.
