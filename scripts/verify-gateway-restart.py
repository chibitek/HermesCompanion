#!/usr/bin/env python3
"""Name: verify-gateway-restart.py
Author: Chibitek Contributors
Date: 2026-09-13
Description: Verify native gateway restart with an open Companion event feed.
Instructions: Run with --server-repo, --python, and a new --artifacts directory.
Uses an isolated Hermes home, ephemeral credential, and no model turns.
"""

import argparse
import asyncio
import json
import os
from pathlib import Path
import secrets
import shutil
import signal
import socket
import subprocess
import tempfile
import time

import aiohttp

CHILD = r'''
import asyncio, os
from pathlib import Path
from hermes_constants import get_hermes_home
from hermes_cli.plugins import discover_plugins
from gateway.config import GatewayConfig, Platform, PlatformConfig
from gateway.run import start_gateway
import gateway.run as source
assert Path(source.__file__).resolve().is_relative_to(Path.cwd().resolve())
assert Path(get_hermes_home()).resolve() == Path(os.environ['HERMES_HOME']).resolve()
discover_plugins()
config = GatewayConfig(platforms={Platform.API_SERVER: PlatformConfig(enabled=True, extra={
    'host': '127.0.0.1', 'port': int(os.environ['API_SERVER_PORT']), 'key': os.environ['API_SERVER_KEY']})},
    sessions_dir=Path(os.environ['HERMES_HOME']) / 'sessions')
asyncio.run(start_gateway(config))
'''


async def verify(args):
    source = args.server_repo.resolve(strict=True)
    runtime = args.python.absolute()
    artifacts = args.artifacts.resolve()
    artifacts.mkdir(parents=True, exist_ok=False)
    key = secrets.token_hex(32)
    with socket.socket() as listener:
        listener.bind(('127.0.0.1', 0))
        port = listener.getsockname()[1]
    base = f'http://127.0.0.1:{port}'
    process = None
    with tempfile.TemporaryDirectory(prefix='hermes-restart-verification-') as home:
        Path(home, 'config.yaml').write_text(json.dumps({
            'plugins': {'enabled': ['hermes-companion']},
            'platform_toolsets': {'api_server': []},
        }))
        shutil.copytree(Path(__file__).resolve().parents[1] / 'GatewayPlugin/hermes-companion',
                        Path(home, 'plugins/hermes-companion'))
        env = {name: os.environ[name] for name in ('PATH', 'HOME', 'USER', 'TMPDIR', 'LANG') if name in os.environ}
        env.update(HERMES_HOME=home, HERMES_KANBAN_HOME=home, API_SERVER_KEY=key,
                   API_SERVER_PORT=str(port), PYTHONPATH=str(source))
        with (artifacts / 'gateway.log').open('w') as log:
            def start():
                return subprocess.Popen([str(runtime), '-u', '-c', CHILD], cwd=source, env=env,
                                        stdout=log, stderr=subprocess.STDOUT)

            async def ready(client, deadline):
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        raise RuntimeError('Isolated gateway exited before API readiness; inspect gateway.log')
                    try:
                        async with client.get(base + '/api/companion/capabilities', timeout=aiohttp.ClientTimeout(total=2)) as response:
                            if response.status == 200:
                                return await response.json()
                    except (aiohttp.ClientError, asyncio.TimeoutError):
                        pass
                    await asyncio.sleep(1)
                raise TimeoutError('Isolated gateway API did not recover within the readiness window')

            async def event(client):
                response = await client.get(base + '/api/companion/changes', timeout=aiohttp.ClientTimeout(total=10))
                if response.status != 200:
                    response.close()
                    raise RuntimeError('Companion event feed was not available')
                assert await response.content.readline() == b'event: workspace.changed\n'
                return response

            try:
                process = start()
                async with aiohttp.ClientSession(headers={'Authorization': 'Bearer ' + key}) as client:
                    before = await ready(client, time.monotonic() + 60)
                    feed = await event(client)
                    print('Isolated gateway is serving; restart requested with an open event feed.', flush=True)
                    process.send_signal(signal.SIGUSR1)
                    deadline = time.monotonic() + 45
                    while process.poll() is None and time.monotonic() < deadline:
                        await asyncio.sleep(0.25)
                    if process.poll() is None:
                        raise TimeoutError('Isolated gateway did not finish graceful shutdown')
                    feed.close()
                    started = time.monotonic()
                    process = start()
                    after = await ready(client, started + 150)
                    recovered_feed = await event(client)
                    recovered_feed.close()
                    elapsed = time.monotonic() - started
                    assert after['version'] == before['version']
                    (artifacts / 'verification.json').write_text(json.dumps({
                        'bridge_version': after['version'], 'recovery_seconds': round(elapsed, 2),
                        'event_feed_before_restart': True, 'event_feed_after_restart': True,
                        'gateway_relaunches': 1,
                    }, indent=2))
                    print(f'API and authenticated event feed recovered after one relaunch in {elapsed:.2f}s.', flush=True)
            finally:
                if process is not None and process.poll() is None:
                    process.terminate()
                    deadline = time.monotonic() + 25
                    while process.poll() is None and time.monotonic() < deadline:
                        await asyncio.sleep(0.25)
                    if process.poll() is None:
                        process.kill()  # Only this verifier's isolated, tool-free child.
                        process.wait(timeout=5)
    print('Isolated gateway stopped; disposable home removed.', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--server-repo', type=Path, required=True)
    parser.add_argument('--python', type=Path, required=True)
    parser.add_argument('--artifacts', type=Path, required=True)
    asyncio.run(verify(parser.parse_args()))
