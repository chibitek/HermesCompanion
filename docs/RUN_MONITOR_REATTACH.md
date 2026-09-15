# Preserve monitoring when reattaching the selected run

## Finding and repair plan

Attaching the run already selected calls `select` again. That replaces the
controller generation and clears live text and its replay cursor. The view's
monitor task is keyed by scene phase and run ID, so the unchanged ID does not
restart monitoring. The old monitor exits on its generation check. An apparently
successful attach can therefore freeze live status and lose displayed output.

Keep the existing selection generation, text and cursor when an attach confirms
the same run. Refresh its authoritative status and clear prior attach/status
errors. Selecting a different run still resets the stream state. Verify by
reattaching during a running monitor, then reconnecting from the existing cursor
and reaching the canonical terminal result without duplicated or lost text.

The correctness pass traces attach through monitor generation checks. The
coherence pass compares those transitions with the SwiftUI task identity: only
a changed run or scene phase should require a replacement monitor. This repair
does not claim to resolve model latency or the retained-session investigation.

## Verification

The new regression failed before repair: reattaching erased the first delta,
never resumed from its cursor and never reached the saved result. With the fix,
the same monitor reconnects from cursor 1, retains A, appends only B and reaches
the canonical AB result. The full suite passed 171 ordinary tests, with eight
opt-in gateway checks skipped and zero failures. Existing replay-gap,
foreign-run and admission/control checks remain green. All eight live checks
passed separately against the real isolated gateway and local model, with zero
retained sessions or metadata.

The repair is archived as 1.8.84 (181), with matching app/widget versions and a
verified signed export. Device inventory confirms installation. Launch was
blocked by the locked phone, so physical visual/audio acceptance is not proven.
Apple processed the upload and build 181 is Testing in the existing internal
group. Build 180 was withdrawn from review; Apple confirmed 1.8.84 (181) submitted
on September 14 at 2:44 AM Eastern and Waiting for Review with manual release
selected. No gateway patch or credential changes were required.
