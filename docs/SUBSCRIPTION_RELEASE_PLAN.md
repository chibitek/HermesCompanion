# Subscription release preparation

Status: requirements prepared; purchases are not implemented or submitted.

## Product decision

The proposed price is approximately USD 1 per month for Hermes Companion. The
paid feature boundary is awaiting confirmation: all Companion features, or a
free core with selected paid features. Users continue to supply their own Hermes
gateway and model access. The subscription must not imply included hosting,
inference credits, or access to every Hermes feature before those features have
been verified.

The exact Apple price point, storefront availability, product identifier, and
subscription group must be verified in App Store Connect before release. No
trial, annual tier, or family-sharing offer is assumed.

## Current evidence

- Build 172 has no StoreKit purchase, transaction listener, entitlement, restore,
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

1. Confirm the paid feature boundary and configure the real subscription record.
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
