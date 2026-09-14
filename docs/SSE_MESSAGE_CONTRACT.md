# Structured streaming message contract

Issue: [#27](https://github.com/chibitek/HermesCompanion/issues/27).

## Finding and scope

What: `SSEEventPayload` accepts a string `message` but silently drops a structured
message object. The current native session-chat gateway sends an assistant ID
and role inside `message.started`. A structured content field is also lost if
present. Malformed message fields are swallowed by `try?` instead of rejected.

How: Trace the native session-chat producer, shared Swift SSE decoder, chat
handler, and durable-run consumer. The current parser already rejects malformed
JSON; the issue's older claim about a raw fallback payload is stale. Existing
coverage checked the start event's name but never its nested fields.

Why: The client should preserve the gateway's message identity and content
without confusing a chat object with error text. A malformed field must not
silently disappear, and diagnostics must identify the contract failure without
recording private payloads.

## Repair plan

- Represent `message` as a string or a typed structured message, preserving the
  existing string-facing error/progress interface and native wire encoding.
- Retain nested ID, role, and content separately; a start event remains an
  acknowledgement and must not insert unconfirmed text into the transcript.
- Reject other message types and invalid typed fields explicitly.
- Add payload-free field diagnostics and debug logging; preserve explicit
  missing-event guidance instead of replacing it with an unnamed-frame error.
- Verify object/string round trips, malformed types, private-text exclusion,
  native acknowledgement handling, the full suite, and real gateway behavior.

This source repair follows build 176 and is not in the submitted Apple binary.

## Verification

The pre-fix regression reported seven failures: loss of the object on re-encoding
and silent acceptance of six invalid message forms. After repair, all **158
ordinary simulator tests passed**, with six opt-in tests skipped. All **six live
gateway tests passed separately**, including a native structured acknowledgement
whose preserved message ID matched the completed response. The first six-test run left one session in its disposable workspace despite
passing the individual checks. The runner rejected that result and removed its
temporary gateway and workspace. The harness now checks for leftover sessions after every test and records bounded
metadata on failure. The repeated six-test run passed all those checks and the
final check with zero sessions remaining. The initial intermittent observation
remains open in [#57](https://github.com/chibitek/HermesCompanion/issues/57);
it is not represented as fixed.

The decoder preserves ID, role and content in their structured representation;
error/progress strings retain their existing behavior and wire format. Parse
failures identify schema fields, and a diagnostic-log regression confirms that
private payload values and unknown event names are excluded. The coherence pass
checked the native producer and both Swift consumers; no gateway or credential
storage change is required.

These fixes and the queue repair are packaged as **1.8.80 (177)**, installed on
the physical phone and accepted for upload by Apple. Launch verification awaits
an unlocked phone. Build 177 is Testing in the internal TestFlight group, but
the existing tester remains Invited and reports the app absent from the active
list. The invitation was resent; TestFlight installation remains unverified.
Build 176 remains the separate submitted Apple review candidate.
