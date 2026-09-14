# Hermes Gateway Compatibility Patches

These reviewed server fixes supplement the Companion bridge. The plugin does
not apply them automatically, and installing the iOS app does not update a
remote Hermes server. Hosted operators must deploy equivalent fixes themselves.

Current validation: September 13, 2026, installed revision `3f86ed75da` on
`main`. All four patches pass a combined `git apply --check` there. The first
two were retested in `/tmp/hermes-server-sync-verification`; event replay uses
`/tmp/hermes-server-events-verification`. Lifecycle progress uses
`/tmp/hermes-server-progress-verification`. None of these checkouts changes the
running gateway. Deployment approval remains outstanding.

## Included Fixes

- `0001-fix-api-resolve-locked-custom-provider-identity-from.patch`: resolves a
  generic `custom` runtime provider from its actual configured endpoint before
  validating a named provider lock. Wrong endpoints and models still fail closed;
  it never infers identity from the requested model or global default.
- `0001-fix-api-enumerate-skills-using-the-current-discovery.patch`: removes an
  unsupported discovery argument that made `/v1/skills` return HTTP 500. The
  existing enabled-skill filtering remains unchanged.

- `0003-run-event-replay-and-fanout.patch`: replaces a run's competing-consumer
  event queue with a bounded replay log and independent viewer cursors. Closing
  one viewer retains the others. `Last-Event-ID` resumes newer events; invalid or
  expired cursors receive `run_replay_gap`, and status reports a recovery cursor.
  The capability response advertises replay/fanout explicitly. Events are retained
  in-process, not across gateway restart. Memory is bounded per run and adapter.

- `0004-run-lifecycle-progress-and-interruptions.patch`: forwards native lease-wait,
  warning, and compression status through `run.progress` events and pollable
  `progress_kind`, `progress_message`, and `progress_at` fields. Free text is
  redacted and bounded. Model output clears a previous wait notice; terminal
  status clears progress and ignores late lifecycle callbacks. Interruptions
  outside the explicit Stop path finish as `interrupted`, not `completed`.

The original provider/skills source commits are `bac8e5f98d` and `e171798ebe`. No authentication or token
storage changes are included. Regression coverage uses temporary profile data,
including real skill discovery and named custom-provider resolution. The API,
session API, and custom-provider identity suites pass: 162 tests, zero failures.

## Historical deployment evidence

The following September 11 evidence is historical. The current source no longer
contains those two fixes and returned the documented errors on September 13.

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
clean development branch, not `main`. The first two patches are commit-format
patches applied with `git am`; the third and fourth are plain diffs applied in order with `git apply`
and then committed on the development branch.
Skip a fix already integrated upstream. If a patch conflicts, stop and review;
do not force it onto a newer release or discard existing local changes.

Run the canonical tests with a Python environment containing the project's test
dependencies:

```sh
scripts/run_tests.sh tests/gateway/test_api_server.py \
  tests/gateway/test_session_api.py tests/hermes_cli/test_custom_provider_identity.py \
  tests/gateway/test_api_server_runs.py tests/gateway/test_api_server_run_fanout.py \
  tests/gateway/test_api_server_run_progress.py tests/agent/test_cross_process_turn_lease.py \
  tests/agent/test_turn_facade_lease.py tests/hermes_state/test_session_turn_lease.py \
  --file-retries 0
```

Restart the gateway gracefully after tests pass, then check the
authenticated skills endpoint and a session turn with a confirmed provider/model
lock. Unit tests alone do not establish successful live deployment.

## Event replay verification

The original two-viewer HTTP test failed with a timeout because the first viewer
consumed the second viewer's event. With the patch, both viewers receive the same
sequence, one disconnect leaves the other intact, and a reconnect receives only
new events. Expired/future cursors fail explicitly. The second invariant test
checks per-run/shared retention, truncation detection, and memory release.

The canonical `scripts/run_tests.sh` run passed 200 tests across the run,
idempotency, import, extraction, base API, and new fanout suites. See
`/tmp/hermes-fanout-reviewed-tests.log`. These use isolated test homes and real
HTTP handlers with a controlled agent; they do not establish live model execution.
Companion build 166 consumes the capability, resumes its cursor, skips duplicates,
and labels output partial after a replay gap. The patch changes neither existing
authorization checks nor credential storage.


## Lifecycle and interruption verification

The status regression first failed because no progress reached the HTTP status
response. The patched canonical test runner passed 116 tests across eight files,
including real SessionDB lease serialization and native facade admission tests.
The expanded HTTP test also passed both normal and interrupted cases, with
streaming and polling checks, credential redaction, wait-to-output transition,
and late-callback rejection. Logs: `/tmp/hermes-progress-native-tests.log` and
`/tmp/hermes-progress-reviewed-native-tests.log`. No model provider is contacted
by these tests; the HTTP boundary uses a controlled agent.
