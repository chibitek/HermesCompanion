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

Build 177 does not contain this source repair. Delivery is pending the next testing build.
