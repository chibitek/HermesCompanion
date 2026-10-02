# Session deletion confirmation

Tracked in issue #58. The client previously discarded the native deletion receipt
and removed local conversation state on any 2xx status. A negative or unrelated
receipt could remove queued drafts without proof of remote deletion.

The repair requires the native object type, the requested session ID, and
`deleted: true` before local removal. Missing or wrongly typed fields, a different
ID, an unexpected object type and a negative acknowledgement each produce a
specific error. Response values are not copied into these diagnostics. Local
conversation, queue and active stream state must survive failed confirmation.

Validation reproduced premature local removal with a negative receipt before the
repair. Afterward, 159 ordinary simulator tests passed, with six live checks
skipped. Regressions cover seven invalid receipts, queue preservation, diagnostic
privacy, and confirmed-deletion races and stream cleanup. All six real disposable
gateway checks passed separately, with zero retained sessions. Existing per-test
cleanup assertions also passed. This gap does not prove the cause of issue #57.

The coherence pass matched the receipt fields against the native gateway producer
and traced the AppStore success and failure branches. No gateway change is needed;
HTTP errors remain handled before receipt decoding. Earlier tests that accepted
an unrelated `ok: true` body now use the native confirmation contract.

This repair is packaged in 1.8.81 (178). The signed export was verified, device
inventory confirms installation, and launching the app succeeded. Apple accepted
the upload, and build 178 is Testing in the internal group. The first
install command lost its device connection, so installation was confirmed by a
separate inventory check. Build 178 replaced the withdrawn build 176 submission and is Waiting for Review
with manual release. Earlier builds 176 and 177 do not contain this repair.
