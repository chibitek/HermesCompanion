# Subscription release preparation

Status: requirements prepared; purchases are not implemented or submitted.

## Product decision

The proposed price is approximately USD 1 per month for Hermes Companion. The
paid tier includes the four experiences specified on September 13, 2026:

| Paid experience | Required product behavior | Current source evidence |
| --- | --- | --- |
| Apple Watch live chat | Send a message, show server/turn state, receive replies, and resume the same conversation across Watch and phone. | No watchOS target or WatchConnectivity implementation. |
| iPad workspace | Resemble Hermes desktop with persistent navigation, conversation/workspace panes, and usable project, Bot, and Kanban views. Adapt to window resizing, keyboard, and pointer input. | Universal iOS target supports iPad, but no dedicated desktop-style split workspace. |
| CarPlay | Voice conversation with listening, server-response, speaking, stop, and reconnection states in an approved driving interface. | Partial scene/controller code exists; the current app entitlements contain no CarPlay grant. |
| Apple Vision Pro | A native visionOS companion with spatial windows for conversations and workspace views, sharing authoritative Hermes sessions and updates. | No visionOS target or native Vision Pro implementation. |

Implementation assumption: core iPhone chat, server management, and existing
phone sync remain free; the subscription unlocks these additional device
experiences. This does not revoke existing phone features or remove access to
saved conversations. Keep basic iPad access separate from the paid desktop-style
workspace rather than using screen size alone as an entitlement decision.

Users continue to supply their own Hermes gateway and model access. The
subscription does not include hosting or inference credits. Planned platforms
must not appear as available purchase benefits until implemented, signed,
approved where required, and verified on the supported device. This scope does
not replace the existing requirement for reliable complete iPhone/Hermes sync.

The exact Apple price point, storefront availability, product identifier, and
subscription group must be verified in App Store Connect before release. No
trial, annual tier, or family-sharing offer is assumed.

## Current evidence

- Build 173 has no StoreKit purchase, transaction listener, entitlement, restore,
  or subscription-management implementation.
- `APP_STORE_SUBMISSION.md` is a historical free-app draft. Its pricing,
  subscription claims, version, and several service descriptions are stale.
- `PRIVACY.md` still references the removed ElevenLabs integration and assumes
  every connection uses Tailscale. The current client also supports configured
  HTTP/HTTPS endpoints. Voice recognition paths require on-device recognition.
- Apple sign-in currently prevents inspection of live subscription records,
  agreements, tax/banking readiness, and tester assignment. An accepted binary
  upload does not prove purchase or TestFlight availability.

## Implementation contract

Use StoreKit 2 and App Store product metadata for localized price and duration.
Resolve access from verified transactions and current entitlement/status data;
never grant paid access from a local Boolean or an unverified transaction.
Observe transaction updates, deliver access before finishing successful
transactions, and re-evaluate access after foregrounding, renewal, expiry,
refund, revocation, or restore. Respect verified billing grace periods.

Keep purchase, pending approval, cancellation, product-loading failure,
verification failure, and restore-with-no-entitlement distinct in the UI.
Restore Purchases and Manage Subscription must remain accessible without paid
access. Preserve server configuration and conversation data when access lapses.
Apply the confirmed paid boundary consistently to text, voice, shortcuts,
widgets, and other entry points. Do not offer a paywall only on the main screen
while alternate entry points bypass the same entitlement policy.

The purchase screen must explain the included functionality, the recurring
period and localized price, and that the user supplies a gateway and model
access. Include working privacy and terms links. Show actual Apple metadata,
not a hardcoded price or a simulated product in a release build.

## Required verification and submission

1. Implement and verify the four paid experiences above, and configure the real
   subscription record with an accurate list of benefits.
2. Verify the App Store account can sell the product. Any new agreement must be
   reviewed and accepted by the account holder through Apple's normal flow.
3. Test real sandbox purchases, restore after reinstall, interrupted/pending
   purchases, cancellation, renewal, expiry, refund/revocation, and offline
   behavior without discarding a still-valid verified entitlement.
4. Verify the confirmed entitlement boundary and core two-way sync on the phone,
   including voice and background/foreground transitions. Complete the existing
   feature coverage review before advertising full parity.
5. Replace the historical submission draft with final screenshots, accurate
   subscription/privacy text, review notes, and reviewer access to a working
   gateway containing no personal information or private production credentials.
6. Add the new app version, subscription group, and first subscription to the
   same App Review submission. Verify Apple's receipt and review status; an
   upload or a draft submission is not submitted approval.

Apple requires the first subscription of its type to accompany a new app
version. See [Submit an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase).
The purchase disclosures, subscriber access, and restore requirements are
covered by [Auto-renewable subscriptions](https://developer.apple.com/app-store/subscriptions/)
and [In-App Purchase](https://developer.apple.com/in-app-purchase/).

## Platform implementation and acceptance

Use one subscription product family across the supported Apple platforms. Verify
its actual App Store Connect platform/product configuration before claiming
cross-device access. Resolve entitlements with StoreKit on supported app targets;
CarPlay uses the containing iPhone app's verified entitlement. Do not send a
trusted `isPaid` Boolean between devices as proof of purchase.

The shared conversation layer must retain server/profile/session identity,
replay cursors, idempotent submission identity, and distinct connection/turn
states. A Watch-to-phone relay must acknowledge durable acceptance separately
from completion and must not duplicate a turn after a disconnect or retry.
Phone unavailability must produce an actionable state. Any direct Watch gateway
mode requires its own verified connectivity design; standalone cellular access
is not assumed simply because the Watch has a network connection.

Each surface must show actual server progress and reconcile remote edits without
manual refresh. Test text/dictation, cancellations, authentication failures,
network loss, foreground recovery, and updates made by a second client. Watch
background execution must follow supported watchOS lifecycle behavior; do not
advertise an uninterrupted background stream without physical-device evidence.

For iPad, validate portrait/landscape, narrow and wide windows, external keyboard,
selection persistence, and independent workspace loading failures. For Vision
Pro, validate native input, accessible text, window lifecycle, and shared-session
consistency rather than relying on an unmodified compatible iPad build.

CarPlay needs the approved category and entitlement before distribution. Apple's
current categories include voice-based conversational apps. The existing
`CPListTemplate` transcript UI and historical audio-entitlement submission text
are not proof of compliance. Review the current guide, request the appropriate
grant, use its allowed templates, and verify the signed binary plus real audio
interruption/reconnection behavior. Purchases and account setup belong on the
phone, outside the driving interaction.

Platform references: [CarPlay](https://developer.apple.com/carplay/),
[Choosing a StoreKit API](https://developer.apple.com/documentation/storekit/choosing-a-storekit-api-for-in-app-purchases),
and [adding platforms](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/).
