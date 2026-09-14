#!/usr/bin/env python3
"""Run real iOS/two-client checks against an isolated local Hermes gateway.

Author: Chibitek Contributors
Updated: 2026-09-14
Usage: supply the server repository, Python runtime, simulator, derived-data,
artifact directory and model arguments shown by --help.

Uses a fresh Hermes home and ephemeral API credential; never edits or restarts an
installed gateway. The default suite has no tools; --approval-check enables only
code execution with one-shot approval for exact disposable file writes. The model endpoint must already be running on loopback.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

GATEWAY = r'''
import asyncio, io, json, os, signal, traceback
from pathlib import Path
from hermes_constants import get_hermes_home
from hermes_cli.config import load_config
from hermes_cli.plugins import discover_plugins
from hermes_cli.tools_config import _get_platform_tools
from gateway.config import PlatformConfig
from gateway.platforms.api_server import APIServerAdapter
from cron.scheduler import tick
import gateway.platforms.api_server as source

assert Path(source.__file__).resolve().is_relative_to(Path.cwd().resolve())
assert Path(get_hermes_home()).resolve() == Path(os.environ["HERMES_HOME"]).resolve()
approval_check = os.environ.get("HERMES_VERIFY_APPROVAL") == "1"
expected_tools = {"code_execution"} if approval_check else set()
assert _get_platform_tools(load_config(), "api_server") == expected_tools, "Unexpected API toolsets"
assert _get_platform_tools(load_config(), "cron") == set(), "Scheduler must have no tools"
assert not (Path.cwd() / ".worktrees").exists(), "Scheduler verification cannot prune source worktrees"
discover_plugins()

async def exercise_native_kanban(stopped):
    # These are the same native operations used by Hermes Desktop, with an
    # isolated home and one runner-owned board. No Companion write route is used.
    from plugins.kanban.dashboard import plugin_api as native
    from starlette.datastructures import UploadFile, Headers
    slug = os.environ["HERMES_VERIFY_KANBAN_BOARD"]
    task_id = child_id = attachment_id = None
    phase = 0
    while not stopped.is_set():
        if slug in {b["slug"] for b in native.list_boards(include_archived=False)["boards"]}:
            if task_id is None:
                board = native.get_board(tenant=None, include_archived=False, board=slug,
                                         workflow_template_id=None, current_step_key=None)
                candidates = [task for column in board["columns"] for task in column["tasks"]
                              if task["title"] == "Phone task verification"]
                if len(candidates) == 1:
                    task_id = candidates[0]["id"]
            if task_id is not None:
                detail = native.get_task(task_id, board=slug, run_state_type=None, run_state_name=None)
                comments = {c["body"] for c in detail["comments"]}
                if phase == 0 and "Phone ready for desktop changes" in comments:
                    child = native.create_task(native.CreateTaskBody(title="Desktop child", parents=[task_id],
                        idempotency_key=slug + "-child"), board=slug)["task"]
                    child_id = child["id"]
                    native.update_task(child_id, native.UpdateTaskBody(status="done", result="Native child result",
                        summary="Native child summary"), board=slug)
                    upload = UploadFile(io.BytesIO("Hermes attachment round trip: café\n".encode()),
                                        filename="desktop-proof.txt", headers=Headers({"content-type": "text/plain"}))
                    receipt = await native.upload_task_attachment(task_id, file=upload, board=slug, uploaded_by="dashboard")
                    attachment_id = receipt["attachment"]["id"]
                    await upload.close()
                    native.update_task(task_id, native.UpdateTaskBody(title="Desktop task update", body="Desktop body retained"), board=slug)
                    native.add_comment(task_id, native.CommentBody(body="Desktop comment arrived", author="dashboard"), board=slug)
                    phase = 1
                elif phase == 1 and "Phone verified desktop attachment" in comments:
                    assert detail["task"]["priority"] == 2
                    assert detail["task"]["body"] == "Desktop body retained"
                    assert detail["task"]["status"] == "done"
                    assert detail["task"]["result"] == "Phone completion result"
                    native.remove_attachment(attachment_id, board=slug)
                    native.delete_task(child_id, board=slug)
                    native.update_task(task_id, native.UpdateTaskBody(title="Desktop removal complete"), board=slug)
                    Path(os.environ["HERMES_VERIFY_KANBAN_REPORT"]).write_text(json.dumps({
                        "native_phone_edit_verified": True, "attachment_removed": True, "child_removed": True}))
                    return
        try:
            await asyncio.wait_for(stopped.wait(), timeout=0.2)
        except asyncio.TimeoutError:
            pass


async def main():
    adapter = APIServerAdapter(PlatformConfig(enabled=True, extra={
        "host": "127.0.0.1", "port": int(os.environ["API_SERVER_PORT"]),
        "key": os.environ["API_SERVER_KEY"],
    }))
    stopped = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stopped.set)
    async def run_scheduler():
        while not stopped.is_set():
            await asyncio.to_thread(tick, verbose=False, sync=True)
            try:
                await asyncio.wait_for(stopped.wait(), timeout=0.25)
            except asyncio.TimeoutError:
                pass
    scheduler = None
    kanban = None
    try:
        if not await adapter.connect():
            raise RuntimeError("Temporary gateway failed to start; inspect gateway.log")
        if not approval_check:
            scheduler = asyncio.create_task(run_scheduler())
            kanban = asyncio.create_task(exercise_native_kanban(stopped))
        def report_native_failure(task):
            if not task.cancelled() and task.exception() is not None:
                traceback.print_exception(task.exception())
        if kanban is not None:
            kanban.add_done_callback(report_native_failure)
        approval_seeded: set[str] = set()

        async def seed_approval_runner():
            from tools.approval import _gateway_queues as _approval_queues, _lock as _approval_lock
            from tools.approval_gateway_wait import _ApprovalEntry
            from gateway.platforms.api_server_runs import _run_event
            while not stopped.is_set():
                for run_id, status in list(adapter._run_statuses.items()):
                    if run_id in approval_seeded:
                        continue
                    if status.get("status") not in {"queued", "running"}:
                        continue
                    approval_seeded.add(run_id)
                    request_id = "seed-" + run_id
                    event = {
                        "request_id": request_id,
                        "command": "execute_code <<'PY'\nfrom pathlib import Path\nPath('verification-native-approval').write_text('Approved by iOS')\nPY",
                        "description": "Write a disposable verification file",
                        "choices": ["once", "session", "always", "deny"],
                        "allow_session": True,
                        "allow_permanent": True,
                    }
                    entry = _ApprovalEntry(dict(event))
                    with _approval_lock:
                        _approval_queues.setdefault(run_id, []).append(entry)
                    adapter._set_run_status(
                        run_id, "waiting_for_approval", last_event="approval.request", approval=dict(entry.data),
                        event_cursor=0)
                    q = adapter._run_streams.get(run_id)
                    if q is not None:
                        q.put_nowait(_run_event(run_id, "approval.request", **dict(entry.data)))
                try:
                    await asyncio.wait_for(stopped.wait(), timeout=0.25)
                except asyncio.TimeoutError:
                    pass

        print("Isolated approval gateway ready" if approval_check else "Isolated gateway and scheduler ready", flush=True)
        approval_task = None
        if approval_check:
            approval_task = asyncio.create_task(seed_approval_runner())
        await stopped.wait()
        if approval_task is not None:
            approval_task.cancel()
            try:
                await approval_task
            except asyncio.CancelledError:
                pass
    finally:
        stopped.set()
        if scheduler is not None:
            await scheduler
        if kanban is not None:
            await kanban
        await adapter.disconnect()

asyncio.run(main())
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--server-repo", type=Path, required=True)
    parser.add_argument("--python", type=Path, required=True)
    parser.add_argument("--simulator", required=True)
    parser.add_argument("--derived-data", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--model-url", default="http://localhost:11434/v1")
    parser.add_argument("--approval-check", action="store_true", help="Run only the real code-execution approval check in a disposable home")
    args = parser.parse_args()
    endpoint = urllib.parse.urlsplit(args.model_url)
    if endpoint.hostname not in {"localhost", "127.0.0.1", "::1"} or endpoint.scheme not in {"http", "https"} or endpoint.username or endpoint.password or endpoint.query or endpoint.fragment:
        parser.error("--model-url must be a loopback HTTP(S) endpoint without credentials, query, or fragment")
    repo = Path(__file__).resolve().parents[1]
    server_repo = args.server_repo.resolve(strict=True)
    runtime = args.python.absolute()
    if not runtime.is_file():
        parser.error("--python must name an existing Python executable")
    artifacts = args.artifacts.resolve()
    artifacts.mkdir(parents=True, exist_ok=False)
    key = secrets.token_hex(32)
    kanban_board = "verify-tasks-" + secrets.token_hex(8)
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    base = f"http://127.0.0.1:{port}"

    def get(path):
        request = urllib.request.Request(base + path, headers={"Authorization": "Bearer " + key})
        with urllib.request.urlopen(request, timeout=5) as response:
            return json.load(response)

    with tempfile.TemporaryDirectory(prefix="hermes-companion-live-") as home:
        # JSON is valid YAML. Configuration contains no credentials; the loopback
        # model does not need one and the gateway key exists only in process env.
        config = {
            "model": {"default": args.model, "provider": "custom:companion-verification", "base_url": args.model_url},
            "custom_providers": [{"name": "companion-verification", "base_url": args.model_url}],
            "platform_toolsets": {"api_server": ["code_execution"] if args.approval_check else [], "cron": []},
            "approvals": {"mode": "manual", "timeout": 120},
            "terminal": {"env_type": "local", "cwd": home},
            "plugins": {"enabled": ["hermes-companion"]},
            "agent": {"max_turns": 2},
        }
        Path(home, "config.yaml").write_text(json.dumps(config))
        project_folder = Path(home, "verification-project")
        reference_folder = Path(home, "verification-reference")
        for folder in (project_folder, reference_folder):
            folder.mkdir()
            (folder / "retain.txt").write_text("Project deletion must retain linked server files.\n")
        shutil.copytree(repo / "GatewayPlugin/hermes-companion", Path(home, "plugins/hermes-companion"))
        env = {name: os.environ[name] for name in ("PATH", "HOME", "USER", "TMPDIR", "LANG") if name in os.environ}
        env.update(HERMES_VERIFY_APPROVAL="1" if args.approval_check else "0", HERMES_HOME=home, HERMES_KANBAN_HOME=home, API_SERVER_KEY=key, API_SERVER_PORT=str(port), PYTHONPATH=str(server_repo),
                   HERMES_VERIFY_KANBAN_BOARD=kanban_board,
                   HERMES_VERIFY_KANBAN_REPORT=str(artifacts / "native-kanban.json"))
        with (artifacts / "gateway.log").open("w") as log:
            process = subprocess.Popen([str(runtime), "-u", "-c", GATEWAY], cwd=server_repo, env=env, stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 45
                while True:
                    if process.poll() is not None:
                        raise RuntimeError("Temporary gateway exited before readiness; inspect gateway.log")
                    try:
                        get("/health")
                        break
                    except (OSError, urllib.error.URLError):
                        if time.monotonic() >= deadline:
                            raise RuntimeError("Temporary gateway did not become ready within 45 seconds")
                        time.sleep(0.25)
                capabilities = get("/v1/capabilities")
                before = get("/api/sessions")
                if before.get("data"):
                    raise RuntimeError("Isolated gateway unexpectedly contains conversations before testing")
                jobs_before = get("/api/jobs?include_disabled=true")
                if jobs_before.get("jobs"):
                    raise RuntimeError("Isolated gateway unexpectedly contains scheduled jobs before testing")
                projects_before = get("/api/companion/project-records?profile=default")
                if projects_before.get("projects") or projects_before.get("active_id"):
                    raise RuntimeError("Isolated gateway unexpectedly contains saved projects before testing")
                print("Temporary gateway ready; running real two-client iOS checks", flush=True)
                test_env = dict(os.environ, TEST_RUNNER_HERMES_LIVE_URL=base, TEST_RUNNER_HERMES_LIVE_KEY=key, TEST_RUNNER_HERMES_DISPOSABLE_WORKSPACE="1",
                                     TEST_RUNNER_HERMES_LIVE_PROJECT_FOLDER=str(project_folder),
                                     TEST_RUNNER_HERMES_LIVE_KANBAN_BOARD=kanban_board,
                                     TEST_RUNNER_HERMES_LIVE_REFERENCE_FOLDER=str(reference_folder),
                                     TEST_RUNNER_HERMES_APPROVAL_FOLDER=home if args.approval_check else "")
                result = artifacts / "ios.xcresult"
                command = ["xcodebuild", "-project", "HermesCompanion.xcodeproj", "-scheme", "HermesCompanion", "-configuration", "Debug",
                           "-destination", "platform=iOS Simulator,id=" + args.simulator, "-derivedDataPath", str(args.derived_data),
                           "-resultBundlePath", str(result), "-collect-test-diagnostics", "never", "-only-testing:HermesCompanionTests/LiveGatewayTests",
                           "CODE_SIGNING_ALLOWED=NO", "test"]
                approval_test = "HermesCompanionTests/LiveGatewayTests/testRealGatewayApprovalControlsReachNativeExecution"
                if args.approval_check:
                    command[command.index("-only-testing:HermesCompanionTests/LiveGatewayTests")] = "-only-testing:" + approval_test
                else:
                    command.insert(-2, "-skip-testing:" + approval_test)
                with (artifacts / "ios.log").open("w") as test_log:
                    tested = subprocess.run(command, cwd=repo, env=test_env, stdout=test_log, stderr=subprocess.STDOUT, timeout=420)
                summary = json.loads(subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)]))
                after = get("/api/sessions")
                jobs_after = get("/api/jobs?include_disabled=true")
                projects_after = get("/api/companion/project-records?profile=default")
                execution_jobs = jobs_after.get("jobs", [])
                cron_output_verified = False
                if len(execution_jobs) == 1:
                    job = execution_jobs[0]
                    job_id = job.get("id", "")
                    if (len(job_id) == 12 and all(c in "0123456789abcdef" for c in job_id)
                            and job.get("name") == "Local scheduler verification"
                            and job.get("last_status") == "ok" and job.get("deliver") == "local"):
                        outputs = list(Path(home, "cron/output", job_id).glob("*.md"))
                        cron_output_verified = len(outputs) == 1 and "READY" in outputs[0].read_text().upper()
                        request = urllib.request.Request(base + "/api/jobs/" + job_id, method="DELETE",
                                                         headers={"Authorization": "Bearer " + key})
                        with urllib.request.urlopen(request, timeout=5) as response:
                            if json.load(response).get("ok") is not True:
                                raise RuntimeError("Scheduler verification job deletion was not confirmed")
                        jobs_after = get("/api/jobs?include_disabled=true")
                linked_files_retained = all((folder / "retain.txt").is_file() and (folder / "retain.txt").read_text() == "Project deletion must retain linked server files.\n"
                                            for folder in (project_folder, reference_folder))
                native_kanban_path = artifacts / "native-kanban.json"
                native_kanban = json.loads(native_kanban_path.read_text()) if native_kanban_path.exists() else {}
                boards_after = get("/api/companion/boards")
                kanban_archived = kanban_board not in {b["slug"] for b in boards_after["boards"]}
                report = {"source": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=server_repo, text=True).strip(),
                          "model": args.model, "features": capabilities.get("features"),
                          "tests": summary, "remaining_sessions": len(after.get("data", [])),
                          "remaining_jobs": len(jobs_after.get("jobs", [])),
                          "cron_output_verified": cron_output_verified,
                          "native_kanban": native_kanban, "kanban_board_archived": kanban_archived,
                          "remaining_projects": len(projects_after.get("projects", [])),
                          "active_project": projects_after.get("active_id"),
                          "linked_project_files_retained": linked_files_retained,
                          "remaining_session_metadata": [
                              {field: row.get(field) for field in ("id", "title", "source", "message_count")}
                              for row in after.get("data", [])]}
                if args.approval_check:
                    report["approval"] = {
                        "seeded_pending_approval": True,
                        "client_resolved_via_native_queue": summary.get("passedTests", 0) >= 1,
                    }
                (artifacts / "verification.json").write_text(json.dumps(report, indent=2))
                if tested.returncode or summary.get("passedTests", 0) < 1 or summary.get("failedTests") or summary.get("skippedTests"):
                    raise RuntimeError("Real iOS verification did not pass; inspect ios.log and verification.json")
                if report["remaining_sessions"]:
                    raise RuntimeError("Verification left conversations in the isolated gateway")
                if not args.approval_check and (not native_kanban or not all(native_kanban.values()) or not kanban_archived):
                    raise RuntimeError("Native Kanban round trip or owned board archive was not verified")
                if not args.approval_check and not cron_output_verified:
                    raise RuntimeError("Scheduler did not persist the expected local verification output")
                if report["remaining_jobs"]:
                    raise RuntimeError("Verification left scheduled jobs in the isolated gateway")
                if report["remaining_projects"] or report["active_project"] or not linked_files_retained:
                    raise RuntimeError("Project lifecycle verification left records or removed linked files")
                if args.approval_check:
                    if not report.get("approval", {}).get("client_resolved_via_native_queue"):
                        raise RuntimeError("Native approval round-trip was not verified")
                    print("Real approval check passed; allowed write verified, denied write absent, sessions removed", flush=True)
                else:
                    print("Real iOS checks passed; chat/jobs/projects removed, owned Kanban board archived, linked files retained", flush=True)
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=20)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=5)
    print("Temporary gateway stopped and its disposable home removed", flush=True)


if __name__ == "__main__":
    main()
