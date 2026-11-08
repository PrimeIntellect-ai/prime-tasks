#!/bin/bash
set -e
mkdir -p /logs/verifier

# Ensure the verifier starts the submitted server itself rather than reusing an
# agent-started process.
pkill -f '/home/user/workspace/server.py' 2>/dev/null || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import asyncio
import ctypes
import json
import math
import os
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile
import time

import pytest
import websockets

WORKSPACE_DIR = "/home/user/workspace"
LIB_PATH = os.path.join(WORKSPACE_DIR, "libmath.so")
TEST_SCRIPT_PATH = os.path.join(WORKSPACE_DIR, "test_integration.py")
OUTPUT_JSON_PATH = os.path.join(WORKSPACE_DIR, "integration_output.json")
SERVER_SCRIPT_PATH = os.path.join(WORKSPACE_DIR, "server.py")
REQUIRED_PAYLOAD = {"op": "variance", "data": [10.5, 15.2, 12.8, 9.1, 14.4]}


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=3)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass


def start_submitted_server():
    return subprocess.Popen(
        [sys.executable, SERVER_SCRIPT_PATH],
        cwd=WORKSPACE_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )


async def websocket_request(payload, proc, attempts=40):
    last_error = None
    for _ in range(attempts):
        if proc.poll() is not None:
            stderr = proc.stderr.read() if proc.stderr else ""
            raise AssertionError(f"server.py exited before accepting connections: {stderr}")
        try:
            async with websockets.connect("ws://localhost:8080", open_timeout=1) as ws:
                await ws.send(json.dumps(payload))
                return await asyncio.wait_for(ws.recv(), timeout=3)
        except Exception as exc:
            last_error = exc
            await asyncio.sleep(0.1)
    raise AssertionError(f"Could not communicate with submitted WebSocket server: {last_error}")


def test_shared_library_compiled():
    assert os.path.exists(LIB_PATH), f"Shared library {LIB_PATH} was not compiled."
    assert os.path.isfile(LIB_PATH), f"{LIB_PATH} is not a file."
    with open(LIB_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{LIB_PATH} is not an ELF shared library."

    lib = ctypes.CDLL(LIB_PATH)
    fn = lib.calculate_variance
    fn.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_int]
    fn.restype = ctypes.c_double

    rng_values = [
        secrets.randbelow(20000) / 137.0 - 50.0
        for _ in range(7)
    ]
    arr = (ctypes.c_double * len(rng_values))(*rng_values)
    actual = fn(arr, len(rng_values))
    mean = sum(rng_values) / len(rng_values)
    expected = sum((x - mean) ** 2 for x in rng_values) / len(rng_values)
    assert math.isclose(actual, expected, rel_tol=1e-10, abs_tol=1e-10), \
        f"calculate_variance returned {actual}, expected {expected}."


def test_integration_script_exists():
    assert os.path.exists(TEST_SCRIPT_PATH), f"Integration test script {TEST_SCRIPT_PATH} is missing."
    assert os.path.isfile(TEST_SCRIPT_PATH), f"{TEST_SCRIPT_PATH} is not a file."


def test_server_script_modified():
    assert os.path.exists(SERVER_SCRIPT_PATH), f"Server script {SERVER_SCRIPT_PATH} is missing."
    with open(SERVER_SCRIPT_PATH, "r") as f:
        content = f.read()
    assert "argtypes" in content, "server.py does not seem to configure 'argtypes' for the C function."
    assert "restype" in content, "server.py does not seem to configure 'restype' for the C function."

    tree = ast.parse(content, filename=SERVER_SCRIPT_PATH)
    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            value = node.value
            for target in targets:
                if isinstance(target, ast.Attribute) and target.attr in ("argtypes", "restype"):
                    assignments[target.attr] = ast.get_source_segment(content, value) or ""
    assert "argtypes" in assignments, "argtypes must be assigned in executable Python code, not merely mentioned in a comment."
    assert "restype" in assignments, "restype must be assigned in executable Python code, not merely mentioned in a comment."
    assert "c_double" in assignments["argtypes"] and "c_int" in assignments["argtypes"], \
        "calculate_variance.argtypes must describe a double pointer and an int."
    assert "c_double" in assignments["restype"], \
        "calculate_variance.restype must be ctypes.c_double."


def test_e2e_artifacts_execute_and_use_ffi():
    # First run the integration script against a verifier-controlled WebSocket
    # peer. This proves it sends the required request and saves the exact bytes
    # it receives, rather than hardcoding integration_output.json.
    token = secrets.token_hex(16)
    exact_response = json.dumps(
        {"result": 5.3, "verifier_token": token, "extra": [1, 2]},
        separators=(", ", ": "),
    )
    capture_request = os.path.join(tempfile.gettempdir(), f"captured-{token}.txt")
    capture_server = os.path.join(tempfile.gettempdir(), f"capture-{token}.py")
    with open(capture_server, "w") as f:
        f.write(r'''import asyncio
import os
import websockets

async def main():
    done = asyncio.Event()
    async def handler(ws):
        message = await ws.recv()
        with open(os.environ["CAPTURE_PATH"], "w") as out:
            out.write(message)
        await ws.send(os.environ["EXACT_RESPONSE"])
        done.set()
    async with websockets.serve(handler, "localhost", 8080):
        print("READY", flush=True)
        await done.wait()

asyncio.run(main())
''')

    env = os.environ.copy()
    env["CAPTURE_PATH"] = capture_request
    env["EXACT_RESPONSE"] = exact_response
    capture_proc = subprocess.Popen(
        [sys.executable, capture_server], stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, env=env, start_new_session=True
    )
    try:
        ready = capture_proc.stdout.readline().strip()
        if ready != "READY":
            raise AssertionError(f"Controlled WebSocket server failed: {capture_proc.stderr.read()}")
        if os.path.exists(OUTPUT_JSON_PATH):
            os.remove(OUTPUT_JSON_PATH)
        run = subprocess.run(
            [sys.executable, TEST_SCRIPT_PATH], cwd=WORKSPACE_DIR,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
        )
        assert run.returncode == 0, f"test_integration.py failed: {run.stderr}"
        capture_proc.wait(timeout=5)
        with open(capture_request, "r") as f:
            sent = json.load(f)
        assert sent == REQUIRED_PAYLOAD, f"Integration test sent {sent}, expected {REQUIRED_PAYLOAD}."
        with open(OUTPUT_JSON_PATH, "r") as f:
            saved = f.read()
        assert saved == exact_response, "test_integration.py did not save the exact received JSON string."
    finally:
        stop_process(capture_proc)
        for path in (capture_request, capture_server):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

    # Exercise the submitted server with verifier-derived inputs, then run the
    # submitted integration script against that server to create the final file.
    server_proc = start_submitted_server()
    try:
        random_data = [secrets.randbelow(50000) / 311.0 - 70.0 for _ in range(9)]
        raw = asyncio.run(websocket_request({"op": "variance", "data": random_data}, server_proc))
        response = json.loads(raw)
        mean = sum(random_data) / len(random_data)
        expected = sum((x - mean) ** 2 for x in random_data) / len(random_data)
        assert math.isclose(response["result"], expected, rel_tol=1e-9, abs_tol=1e-9), \
            f"Server returned {response['result']}, expected {expected}."

        if os.path.exists(OUTPUT_JSON_PATH):
            os.remove(OUTPUT_JSON_PATH)
        run = subprocess.run(
            [sys.executable, TEST_SCRIPT_PATH], cwd=WORKSPACE_DIR,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
        )
        assert run.returncode == 0, f"test_integration.py failed against server.py: {run.stderr}"
    finally:
        stop_process(server_proc)

    # Replace the library temporarily with a verifier-generated implementation.
    # A server that really calls calculate_variance must expose its unpredictable
    # result; a Python hardcoded variance implementation cannot pass this check.
    backup = os.path.join(tempfile.gettempdir(), f"libmath-{token}.so")
    probe_c = os.path.join(tempfile.gettempdir(), f"probe-{token}.c")
    shutil.copy2(LIB_PATH, backup)
    magic = 10000.0 + secrets.randbelow(100000) / 97.0
    scale = 0.25 + secrets.randbelow(1000) / 997.0
    try:
        with open(probe_c, "w") as f:
            f.write(
                "double calculate_variance(double *data, int length) { "
                f"return {magic!r} + data[0] * {scale!r} + length * 0.125; }}\n"
            )
        subprocess.run(["gcc", "-shared", "-fPIC", probe_c, "-o", LIB_PATH], check=True)
        probe_proc = start_submitted_server()
        try:
            probe_data = [secrets.randbelow(10000) / 173.0, 4.25, -8.5]
            raw = asyncio.run(websocket_request({"op": "variance", "data": probe_data}, probe_proc))
            result = json.loads(raw)["result"]
            expected_probe = magic + probe_data[0] * scale + len(probe_data) * 0.125
            assert math.isclose(result, expected_probe, rel_tol=1e-12, abs_tol=1e-9), \
                "server.py did not return the value produced by calculate_variance in libmath.so."
        finally:
            stop_process(probe_proc)
    finally:
        shutil.copy2(backup, LIB_PATH)
        for path in (backup, probe_c):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass


def test_integration_output_correct():
    assert os.path.exists(OUTPUT_JSON_PATH), f"Output JSON file {OUTPUT_JSON_PATH} is missing. Did you run the integration test?"

    with open(OUTPUT_JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{OUTPUT_JSON_PATH} does not contain valid JSON.")

    assert "result" in data, f"'result' key missing in {OUTPUT_JSON_PATH}."

    # The variance of [10.5, 15.2, 12.8, 9.1, 14.4] is exactly 5.3
    expected_variance = 5.3
    actual_variance = data["result"]

    assert isinstance(actual_variance, (int, float)), f"Result should be a number, got {type(actual_variance)}"
    assert math.isclose(actual_variance, expected_variance, rel_tol=1e-4), \
        f"Expected variance approximately {expected_variance}, got {actual_variance}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
