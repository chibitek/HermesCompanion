# Hermes Gateway Compatibility Patches

These reviewed server fixes supplement the Companion bridge. The plugin does
not apply them automatically, and installing the iOS app does not update a
remote Hermes server. Hosted operators must deploy equivalent fixes themselves.

Tested against Hermes upstream `53e32d0581` (0.21.2), with the local development
branch's session provider/workspace metadata changes retained.

## Included Fixes

- `0001-fix-api-resolve-locked-custom-provider-identity-from.patch`: resolves a
  generic `custom` runtime provider from its actual configured endpoint before
  validating a named provider lock. Wrong endpoints and models still fail closed;
  it never infers identity from the requested model or global default.
- `0001-fix-api-enumerate-skills-using-the-current-discovery.patch`: removes an
  unsupported discovery argument that made `/v1/skills` return HTTP 500. The
  existing enabled-skill filtering remains unchanged.

The source commits are `bac8e5f98d` and `e171798ebe`. No authentication or token
storage changes are included. Regression coverage uses temporary profile data,
including real skill discovery and named custom-provider resolution. The API,
session API, and custom-provider identity suites pass: 162 tests, zero failures.

Live verification on September 11, 2026: `/v1/skills` returned HTTP 200 with 286
entries; the bridge returned ten project profile groups without errors, ten Bot
profiles, and two boards. A separate diagnostic session returned HTTP 200 with
provider `custom:local-(localhost:11434)`, model `qwen3.8:27b-mlx`, and
`model_lock: confirmed`. The diagnostic session was then deleted successfully.

The first graceful restart hit a transient macOS port-8642 bind failure. After
the old process exited and the port was confirmed free, a second graceful
restart restored the API. This restart edge case is not fixed by these patches;
always verify the HTTP listener rather than relying only on service status.

## Applying to a Compatible Checkout

Review the patches against the installed Hermes version first. Start from a
clean development branch, not `main`, and apply each patch once with `git am`.
Skip a fix already integrated upstream. If a patch conflicts, stop and review;
do not force it onto a newer release or discard existing local changes.

Run `scripts/run_tests.sh tests/gateway/test_api_server.py
tests/gateway/test_session_api.py tests/hermes_cli/test_custom_provider_identity.py`
as a single command, using a Python environment with the project's test
dependencies. Restart the gateway gracefully after tests pass, then check the
authenticated skills endpoint and a session turn with a confirmed provider/model
lock. Unit tests alone do not establish successful live deployment.

## Local Deployment Note

The development Mac's installed Hermes checkout now uses `Dev_Erick`. Its legacy
`~/.hermes/scripts/reapply-hermes-patch.sh` watchdog was guarded to exit outside
`main`, so switching development commits cannot replay its historical patch.
That host-specific guard is not part of these portable patches. Future Hermes
updates must preserve reviewed local changes or replace them with upstream fixes.
