# Active chat guidance

## Problem and behavior

The busy composer previously saved every follow-up for a later turn even when
Hermes advertised native active-run steering. It also dropped `pending_steer`,
which reports guidance accepted but not consumed before a run finished. That
could hide instructions sent from another client.

The composer now uses `POST /v1/runs/{id}/steer` when the current conversation
has an active run and the server advertises `run_steer`. It retains the queued
fallback when no run is steerable or earlier work needs delivery or review.
Guidance never jumps ahead of an older queued message.

## Delivery and recovery

Text is persisted with its server, conversation and run before submission.
Own guidance requests are serialized without blocking the stream reader or
composer. The UI distinguishes sending from server acceptance. Acceptance is
not consumption: accepted entries remain until the terminal receipt confirms
no undelivered guidance.

Timeouts, rejected or mismatched receipts, navigation and incomplete streams
retain drafts for explicit review. They do not cancel the main chat or trigger
automatic retries. Late acknowledgements cannot mutate another conversation.
Terminal events arriving before HTTP acknowledgements are handled in either order.

When Hermes returns undelivered guidance, local drafts stay recoverable and the
exact server text is also retained if not already represented. This preserves
instructions from another client and combined server buffers. Local drafts may
already be included in that buffer; the UI asks the user to review history before
resending. Replayed terminal events do not append duplicates. Restored in-flight
entries require review after restart.

## Verification

A regression first demonstrated that undelivered remote text was lost when a
local guidance entry existed. The repaired full suite passes 168 ordinary tests;
seven opt-in real-gateway checks are run separately. Coverage includes receipt
ordering, rejection, timeout, serialized submissions, foreign-session isolation,
older queued work, and recovery without automatic replay.

Two independent clients exercise native steering during a real model response.
Every accepted marker must appear in canonical history or the server's pending
buffer and Companion recovery list. The isolated runner also requires deletion
of all diagnostic sessions. All seven real-gateway checks passed with zero remaining sessions or session
metadata. This run observed first response activity at 7.703 seconds, steering
acceptance at 7.717 seconds and completion at 17.407 seconds. An earlier single
client probe took roughly 110 seconds; latency remains tracked separately in #55.
The repair is being packaged as 1.8.82 (179); Apple delivery is not yet verified.

No authentication, credential storage, or production gateway changes are needed.
This repair does not establish complete Hermes parity or resolve model latency.
