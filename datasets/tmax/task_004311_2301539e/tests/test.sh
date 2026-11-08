#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop the mock server the agent was instructed to leave running so the
# behavioral test can exercise the submitted client on fresh input.
python3 - <<'PY'
import os
import signal
import time

for name in os.listdir('/proc'):
    if not name.isdigit():
        continue
    try:
        with open(f'/proc/{name}/cmdline', 'rb') as f:
            cmdline = f.read().replace(b'\0', b' ')
        if b'/home/user/mock_server.py' in cmdline:
            os.kill(int(name), signal.SIGTERM)
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        pass
time.sleep(0.5)
PY

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import json
import os
import py_compile
import random
import secrets
import stat
import subprocess
import sys

import pytest
import websockets


def test_ci_report_exists():
    """Verify that the ci_report.json file was created."""
    report_path = "/home/user/ci_report.json"
    assert os.path.isfile(report_path), f"The file {report_path} was not created."


def test_ci_report_content():
    """Verify that the ci_report.json contains the correct evaluation results."""
    report_path = "/home/user/ci_report.json"

    try:
        with open(report_path, "r") as f:
            report_data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {report_path} does not contain valid JSON.")

    expected_data = {
        "lib-alpha": "ACCEPTED",
        "lib-beta": "REJECTED",
        "lib-gamma": "REJECTED",
        "lib-delta": "ACCEPTED",
        "lib-epsilon": "ACCEPTED"
    }

    assert isinstance(report_data, dict), "The JSON root must be a dictionary."

    for pkg, status in expected_data.items():
        assert pkg in report_data, f"Package '{pkg}' is missing from the report."
        assert report_data[pkg] == status, f"Expected '{pkg}' to be '{status}', but got '{report_data[pkg]}'."

    extra_keys = set(report_data.keys()) - set(expected_data.keys())
    assert not extra_keys, f"Found unexpected packages in the report: {extra_keys}"


def _policy(old, new):
    old_parts = tuple(int(x) for x in old.split('.'))
    new_parts = tuple(int(x) for x in new.split('.'))
    if new_parts < old_parts or new_parts[0] > old_parts[0]:
        return "REJECTED"
    return "ACCEPTED"


def test_ci_monitor_executes_and_processes_fresh_fragmented_stream():
    monitor_path = "/home/user/ci_monitor.py"
    assert os.path.isfile(monitor_path), f"The file {monitor_path} was not created."
    assert stat.S_ISREG(os.stat(monitor_path).st_mode), "ci_monitor.py must be a regular file."

    try:
        py_compile.compile(monitor_path, doraise=True)
    except py_compile.PyCompileError as exc:
        pytest.fail(f"ci_monitor.py is not valid Python: {exc}")

    token = secrets.token_hex(6)
    rng = random.SystemRandom()
    major = rng.randint(2, 20)
    minor = rng.randint(2, 30)
    patch = rng.randint(2, 30)

    records = [
        {"pkg": f"minor-{token}", "old": f"{major}.{minor}.{patch}", "new": f"{major}.{minor + 1}.0"},
        {"pkg": f"patch-{token}", "old": f"{major}.{minor}.{patch}", "new": f"{major}.{minor}.{patch + 1}"},
        {"pkg": f"patch-down-{token}", "old": f"{major}.{minor}.{patch}", "new": f"{major}.{minor}.{patch - 1}"},
        {"pkg": f"minor-down-{token}", "old": f"{major}.{minor}.{patch}", "new": f"{major}.{minor - 1}.{patch}"},
        {"pkg": f"major-up-{token}", "old": f"{major}.{minor}.{patch}", "new": f"{major + 1}.0.0"},
        {"pkg": f"major-down-{token}", "old": f"{major}.{minor}.{patch}", "new": f"{major - 1}.{minor}.{patch}"},
    ]
    rng.shuffle(records)
    expected = {r["pkg"]: _policy(r["old"], r["new"]) for r in records}

    stream = ''.join(json.dumps(r) + '\n' for r in records)
    chunks = []
    pos = 0
    while pos < len(stream):
        size = rng.randint(1, 5)
        chunks.append(stream[pos:pos + size])
        pos += size

    report_path = "/home/user/ci_report.json"
    if os.path.exists(report_path):
        os.unlink(report_path)

    async def run_test():
        async def handler(websocket, *args):
            for chunk in chunks:
                await websocket.send(chunk)
                await asyncio.sleep(0.001)
            await websocket.send("EOF")

        async with websockets.serve(handler, "localhost", 8765):
            proc = await asyncio.create_subprocess_exec(
                sys.executable,
                monitor_path,
                cwd="/home/user",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            try:
                stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=20)
            except asyncio.TimeoutError:
                proc.kill()
                await proc.communicate()
                pytest.fail("ci_monitor.py did not exit after receiving EOF.")

            assert proc.returncode == 0, (
                f"ci_monitor.py exited with status {proc.returncode}.\n"
                f"stdout: {stdout.decode(errors='replace')}\n"
                f"stderr: {stderr.decode(errors='replace')}"
            )

    asyncio.run(run_test())

    assert os.path.isfile(report_path), "ci_monitor.py did not create ci_report.json when executed."
    try:
        with open(report_path, "r") as f:
            actual = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"The dynamically generated report is not valid JSON: {exc}")

    assert isinstance(actual, dict), "The dynamically generated report must be a dictionary."
    assert actual == expected, (
        "ci_monitor.py did not correctly parse and evaluate the fresh fragmented stream. "
        f"Expected {expected}, got {actual}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
