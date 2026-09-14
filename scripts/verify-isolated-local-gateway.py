#!/usr/bin/env python3
"""Run real iOS/two-client tests against an isolated, tool-free local Hermes gateway.

Author: Chibitek Contributors
Updated: 2026-09-14
Usage: supply the server repository, Python runtime, simulator, derived-data,
artifact directory and model arguments shown by --help.

Uses a fresh Hermes home and ephemeral API credential; never edits or restarts an
installed gateway. The model endpoint must already be running on loopback.
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
import asyncio, os, signal
from pathlib import Path
from hermes_constants import get_hermes_home
from hermes_cli.config import load_config
from hermes_cli.plugins import discover_plugins
from hermes_cli.tools_config import _get_platform_tools
from gateway.config import PlatformConfig
from gateway.platforms.api_server import APIServerAdapter
import gateway.platforms.api_server as source

assert Path(source.__file__).resolve().is_relative_to(Path.cwd().resolve())
assert Path(get_hermes_home()).resolve() == Path(os.environ["HERMES_HOME"]).resolve()
assert _get_platform_tools(load_config(), "api_server") == set(), "Verification must have no tools enabled"
discover_plugins()

async def main():
    adapter = APIServerAdapter(PlatformConfig(enabled=True, extra={
        "host": "127.0.0.1", "port": int(os.environ["API_SERVER_PORT"]),
        "key": os.environ["API_SERVER_KEY"],
    }))
    stopped = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stopped.set)
    try:
        if not await adapter.connect():
            raise RuntimeError("Temporary gateway failed to start; inspect gateway.log")
        print("Isolated gateway ready", flush=True)
        await stopped.wait()
    finally:
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
            "platform_toolsets": {"api_server": []},
            "plugins": {"enabled": ["hermes-companion"]},
            "agent": {"max_turns": 2},
        }
        Path(home, "config.yaml").write_text(json.dumps(config))
        shutil.copytree(repo / "GatewayPlugin/hermes-companion", Path(home, "plugins/hermes-companion"))
        env = {name: os.environ[name] for name in ("PATH", "HOME", "USER", "TMPDIR", "LANG") if name in os.environ}
        env.update(HERMES_HOME=home, HERMES_KANBAN_HOME=home, API_SERVER_KEY=key, API_SERVER_PORT=str(port), PYTHONPATH=str(server_repo))
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
                print("Temporary gateway ready; running real two-client iOS conversation test", flush=True)
                test_env = dict(os.environ, TEST_RUNNER_HERMES_LIVE_URL=base, TEST_RUNNER_HERMES_LIVE_KEY=key, TEST_RUNNER_HERMES_DISPOSABLE_WORKSPACE="1")
                result = artifacts / "ios.xcresult"
                command = ["xcodebuild", "-project", "HermesCompanion.xcodeproj", "-scheme", "HermesCompanion", "-configuration", "Debug",
                           "-destination", "platform=iOS Simulator,id=" + args.simulator, "-derivedDataPath", str(args.derived_data),
                           "-resultBundlePath", str(result), "-collect-test-diagnostics", "never", "-only-testing:HermesCompanionTests/LiveGatewayTests",
                           "CODE_SIGNING_ALLOWED=NO", "test"]
                with (artifacts / "ios.log").open("w") as test_log:
                    tested = subprocess.run(command, cwd=repo, env=test_env, stdout=test_log, stderr=subprocess.STDOUT, timeout=420)
                summary = json.loads(subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)]))
                after = get("/api/sessions")
                report = {"source": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=server_repo, text=True).strip(),
                          "model": args.model, "features": capabilities.get("features"),
                          "tests": summary, "remaining_sessions": len(after.get("data", [])),
                          "remaining_session_metadata": [
                              {field: row.get(field) for field in ("id", "title", "source", "message_count")}
                              for row in after.get("data", [])]}
                (artifacts / "verification.json").write_text(json.dumps(report, indent=2))
                if tested.returncode or summary.get("passedTests", 0) < 1 or summary.get("failedTests") or summary.get("skippedTests"):
                    raise RuntimeError("Real iOS verification did not pass; inspect ios.log and verification.json")
                if report["remaining_sessions"]:
                    raise RuntimeError("Verification left conversations in the isolated gateway")
                print("Real two-client iOS conversation passed; diagnostic conversations removed", flush=True)
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
