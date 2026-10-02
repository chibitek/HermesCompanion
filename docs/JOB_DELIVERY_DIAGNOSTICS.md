# Scheduled-job delivery diagnostics

## Problem and behavior

Hermes records execution errors separately from delivery errors and receipts.
Companion decoded only the execution error. A successful model run with a failed
send could show the raw delivery_failed status while hiding the actual delivery
reason. Queued or unverified acknowledgements also lost their details. The only
error view was limited to two lines.

The job model now retains delivery errors, queued receipts and unverified targets.
Execution completion is labeled independently from delivery. Expandable diagnostic
rows show the complete server reason and allow copying it. Queued targets are not
also listed as unverified, and unverified acknowledgements are never labeled as
confirmed delivery. If the server reports delivery_failed without a reason, the
app explicitly says so and points to the job log and target configuration.

The existing live job snapshot replaces all outcome fields, so recovery removes
old failure diagnostics without dismissing unrelated platform errors.

## Verification

Unit contracts cover execution success with delivery failure, reason preservation,
recovery, queued versus unverified receipts, duplicate targets and older gateways
that omit detailed delivery fields.

The real isolated test uses a job created through the API with deliver=origin.
Its origin is the API server's local return channel, which cannot deliver the
scheduled output. No external recipient or messaging service is configured.
The test observes the actual native delivery failure through live AppStore sync,
then changes the job to local output from a second client and runs it again.
It verifies successful recovery and the removal of delivery errors on both clients,
then deletes the owned job and execution conversations.

Physical disclosure interaction, accessibility and external messaging delivery
remain acceptance work. This does not claim complete scheduled-job feature parity.

The live run passed all twelve checks with zero failures or skips. The delivery
failure/recovery check took 6.07 seconds. Final canonical reads contained zero
jobs, sessions, projects or active selection; linked files were unchanged and the
separate scheduler check verified its saved local output.

## Request-body verification repair

The full simulator suite reproduced an empty retry-body capture in issue #66.
A real Foundation bound stream reproduced the reader defect: with the stream
open but its producer still preparing bytes, hasBytesAvailable was false and the
old helper returned zero bytes instead of the complete 43-byte JSON request.
The regression failed before the helper repair and passed afterward, together
with the original durable admission test. The helper now reads until EOF instead
of treating availability as completion. Input, session and idempotency assertions
remain intact; production admission code is unchanged.

The next full run also captured a third request with no admission key between
both valid admissions. The prior live-sync test had canceled an unstructured
workspace watcher without joining it. runLiveSync now owns the watcher in a
structured task group and cancels and joins it before returning. The admission
contract also explicitly checks that each captured request is POST /v1/runs,
so unrelated leaked requests cannot silently count as retry bodies.

The full simulator suite after both repairs passed 177 ordinary tests with
zero failures; twelve real-gateway checks run separately.

The final twelve real-gateway checks also passed after the shutdown repair,
with zero retained records, unchanged linked files and saved output verified.
