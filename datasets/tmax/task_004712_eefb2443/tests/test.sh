#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import asyncio
import contextlib
import json
import os
import random
import re
import signal
import subprocess
import time

import pytest
import websockets

BINARY = "/home/user/ws_server/target/release/ws_server"
PROJECT = "/home/user/ws_server"


def test_binary_exists():
    binary_path = BINARY
    assert os.path.isfile(binary_path), f"Compiled binary not found at {binary_path}. Did you successfully compile the Rust project?"
    assert os.access(binary_path, os.X_OK), f"File at {binary_path} is not executable."


def test_test_results():
    results_path = "/home/user/test_results.json"
    assert os.path.isfile(results_path), f"{results_path} not found. Did you run the test_client.py script?"

    with open(results_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Could not parse {results_path} as valid JSON.")

    assert data.get("success") is True, f"Expected 'success' to be true in {results_path}, but got {data.get('success')}."


def test_memory_profile_exists():
    profile_path = "/home/user/memory_profile.txt"
    assert os.path.isfile(profile_path), f"{profile_path} not found. Did you run the server under the time command?"

    with open(profile_path, "r") as f:
        content = f.read()

    assert "Maximum resident set size (kbytes):" in content, f"{profile_path} does not contain the expected output from '/usr/bin/time -v'."
    assert "Command being timed:" in content, f"{profile_path} does not look like complete '/usr/bin/time -v' output."
    assert BINARY in content, f"{profile_path} does not show that the required server binary was profiled."
    assert re.search(r"Exit status:\s*0(?:\D|$)", content), f"The profiled server did not exit successfully according to {profile_path}."


def test_max_memory_value():
    profile_path = "/home/user/memory_profile.txt"
    max_memory_path = "/home/user/max_memory.txt"

    assert os.path.isfile(profile_path), f"{profile_path} is missing."
    assert os.path.isfile(max_memory_path), f"{max_memory_path} not found. Did you extract the memory value?"

    with open(profile_path, "r") as f:
        content = f.read()

    match = re.search(r"Maximum resident set size \(kbytes\):\s*(\d+)", content)
    assert match is not None, f"Could not find 'Maximum resident set size (kbytes):' in {profile_path}."
    expected_val = int(match.group(1))

    with open(max_memory_path, "r") as f:
        val_str = f.read().strip()

    assert val_str.isdigit(), f"{max_memory_path} does not contain a valid integer. Found: '{val_str}'"
    actual_val = int(val_str)

    assert actual_val == expected_val, f"Value in {max_memory_path} ({actual_val}) does not match the value extracted from {profile_path} ({expected_val})."
    assert actual_val > 0, "Maximum resident set size must be positive."


async def connect_with_retry():
    last_error = None
    for _ in range(50):
        try:
            return await websockets.connect("ws://127.0.0.1:8080")
        except Exception as exc:
            last_error = exc
            await asyncio.sleep(0.1)
    raise AssertionError(f"Server did not start listening on port 8080: {last_error}")


async def exercise_server():
    rng = random.SystemRandom()

    # Use multiple connections to exercise the ownership fix across spawned tasks.
    cases = []
    for _ in range(6):
        values = [rng.randint(-10000, 10000) for _ in range(rng.randint(1, 20))]
        cases.append(values)

    for values in cases:
        ws = await connect_with_retry()
        try:
            await ws.send(json.dumps({"action": "process", "data": values}))
            response = json.loads(await asyncio.wait_for(ws.recv(), timeout=3))
            assert response["status"] == "RustTestServer"
            assert response["sum"] == sum(values)
        finally:
            with contextlib.suppress(Exception):
                await ws.close()

    # Exercise a burst comparable to the required load test, with answers derived
    # by the verifier rather than read from agent-created files.
    ws = await connect_with_retry()
    try:
        for _ in range(100):
            values = [rng.randint(-1000, 1000) for _ in range(rng.randint(1, 12))]
            await ws.send(json.dumps({"action": "process", "data": values}))
            response = json.loads(await asyncio.wait_for(ws.recv(), timeout=3))
            assert response == {"status": "RustTestServer", "sum": sum(values)}
        await ws.send(json.dumps({"action": "shutdown", "data": []}))
    finally:
        with contextlib.suppress(Exception):
            await ws.close()


def test_release_build_and_websocket_behavior_under_time():
    subprocess.run(["pkill", "-x", "ws_server"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    time.sleep(0.2)

    build = subprocess.run(
        ["cargo", "build", "--release", "--offline"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert build.returncode == 0, "cargo build --release failed:\n" + build.stdout[-8000:]
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Release artifact is not an ELF executable."

    verifier_profile = "/tmp/verifier_memory_profile.txt"
    with contextlib.suppress(FileNotFoundError):
        os.unlink(verifier_profile)

    proc = subprocess.Popen(
        ["/usr/bin/time", "-v", "-o", verifier_profile, BINARY],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    try:
        asyncio.run(exercise_server())
        returncode = proc.wait(timeout=15)
        assert returncode == 0, f"Server/time process exited with status {returncode}."
    finally:
        if proc.poll() is None:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(proc.pid, signal.SIGTERM)
            with contextlib.suppress(subprocess.TimeoutExpired):
                proc.wait(timeout=3)
        if proc.poll() is None:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(proc.pid, signal.SIGKILL)

    assert os.path.isfile(verifier_profile), "Independent /usr/bin/time profile was not produced."
    with open(verifier_profile, "r") as f:
        profile = f.read()
    rss = re.search(r"Maximum resident set size \(kbytes\):\s*(\d+)", profile)
    assert rss and int(rss.group(1)) > 0, "Independent memory profile has no valid maximum RSS."
    assert re.search(r"Exit status:\s*0(?:\D|$)", profile), "Profiled server did not shut down cleanly."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
