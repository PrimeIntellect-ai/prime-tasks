#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import math
import os
import random
import struct
import subprocess
import sys
import time

import pytest

PROJECT = "/home/user/project"
SO_PATH = os.path.join(PROJECT, "libalgo.so")
SERVER_SCRIPT = os.path.join(PROJECT, "ws_server.py")
LOG_FILE = os.path.join(PROJECT, "server_ready.log")


def test_makefile_builds_shared_library_with_pic():
    clean = subprocess.run(
        ["make", "clean"], cwd=PROJECT, capture_output=True, text=True
    )
    assert clean.returncode == 0, f"make clean failed: {clean.stdout}\n{clean.stderr}"
    assert not os.path.exists(SO_PATH), "make clean did not remove libalgo.so"

    dry_run = subprocess.run(
        ["make", "-B", "-n"], cwd=PROJECT, capture_output=True, text=True
    )
    assert dry_run.returncode == 0, f"make dry-run failed: {dry_run.stdout}\n{dry_run.stderr}"
    commands = (dry_run.stdout + dry_run.stderr).lower()
    assert "-fpic" in commands, "The Makefile build does not compile with -fPIC/-fpic"
    assert "-shared" in commands, "The Makefile build does not link with -shared"

    build_started = time.time()
    build = subprocess.run(
        ["make"], cwd=PROJECT, capture_output=True, text=True
    )
    assert build.returncode == 0, f"make failed: {build.stdout}\n{build.stderr}"
    assert os.path.exists(SO_PATH), "Running make did not create libalgo.so"
    assert os.path.getmtime(SO_PATH) >= build_started - 1, "make did not freshly build libalgo.so"

    with open(SO_PATH, "rb") as f:
        header = f.read(20)
    assert header[:4] == b"\x7fELF", "libalgo.so is not an ELF artifact"
    endian = "<" if header[5] == 1 else ">" if header[5] == 2 else None
    assert endian is not None, "libalgo.so has an invalid ELF byte order"
    assert struct.unpack(endian + "H", header[16:18])[0] == 3, "libalgo.so is not an ELF shared object"


def test_libalgo_exists_and_works():
    assert os.path.exists(SO_PATH), f"{SO_PATH} does not exist. Did you modify the Makefile and run make?"

    try:
        lib = ctypes.CDLL(SO_PATH)
    except Exception as e:
        pytest.fail(f"Failed to load {SO_PATH} as a shared library: {e}")

    try:
        lib.compute_root.argtypes = [ctypes.c_double]
        lib.compute_root.restype = ctypes.c_double
    except AttributeError:
        pytest.fail("Function 'compute_root' is not exported by the shared library.")

    result = lib.compute_root(81.0)
    assert abs(result - 9.0) < 1e-5, f"compute_root(81.0) returned {result}, expected ~9.0"

    rng = random.SystemRandom()
    values = [2.0, 3.5, 10.24, 123.456] + [rng.uniform(1.01, 10000.0) for _ in range(5)]
    for value in values:
        result = lib.compute_root(value)
        expected = math.sqrt(value)
        assert abs(result - expected) < 1e-5, (
            f"compute_root({value}) returned {result}, expected approximately {expected}"
        )


def start_server():
    if os.path.exists(LOG_FILE):
        os.remove(LOG_FILE)

    proc = subprocess.Popen(
        [sys.executable, SERVER_SCRIPT],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    ready = False
    for _ in range(50):
        if os.path.exists(LOG_FILE):
            with open(LOG_FILE, "r") as f:
                if "SERVER READY" in f.read():
                    ready = True
                    break
        if proc.poll() is not None:
            break
        time.sleep(0.1)

    assert ready, "Server did not write 'SERVER READY' to /home/user/project/server_ready.log within 5 seconds."
    return proc


def stop_server(proc):
    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)


def websocket_results(values):
    client_code = r'''
import asyncio
import json
import sys
import websockets

values = json.loads(sys.argv[1])

async def run_client():
    try:
        async with websockets.connect("ws://localhost:8765") as ws:
            results = []
            for value in values:
                await ws.send(repr(value))
                results.append(float(await ws.recv()))
            print("SUCCESS:" + json.dumps(results))
    except Exception as e:
        print(f"ERROR:{e}")

asyncio.run(run_client())
'''
    client_proc = subprocess.run(
        [sys.executable, "-c", client_code, json.dumps(values)],
        capture_output=True,
        text=True,
        timeout=5,
    )
    output = client_proc.stdout.strip()
    assert "SUCCESS" in output, (
        f"WebSocket client test failed. Output: {output} | Error: {client_proc.stderr}"
    )
    line = next((line for line in output.splitlines() if line.startswith("SUCCESS:")), None)
    assert line is not None, f"WebSocket client produced no result list: {output}"
    return json.loads(line.split(":", 1)[1])


def test_ws_server_behavior():
    assert os.path.exists(SERVER_SCRIPT), f"{SERVER_SCRIPT} does not exist."
    rng = random.SystemRandom()
    values = [81.0, 2.0, 7.25, 250.75] + [rng.uniform(1.01, 5000.0) for _ in range(4)]

    proc = start_server()
    try:
        results = websocket_results(values)
        assert len(results) == len(values)
        for value, result in zip(values, results):
            expected = math.sqrt(value)
            assert abs(result - expected) < 1e-5, (
                f"WebSocket result for {value} was {result}, expected approximately {expected}"
            )
    finally:
        stop_server(proc)


def test_ws_server_calls_the_c_function():
    # Substitute a runtime-generated ABI-compatible library. A compliant server
    # must expose this library's results rather than calculating roots in Python.
    backup = SO_PATH + ".verifier-backup"
    probe_source = "/tmp/libalgo_probe.c"
    rng = random.SystemRandom()
    multiplier = rng.uniform(1.5, 4.5)
    offset = rng.uniform(1000.0, 9000.0)
    values = [rng.uniform(1.1, 100.0) for _ in range(4)]

    with open(probe_source, "w") as f:
        f.write(
            "double compute_root(double n) { return n * %.17g + %.17g; }\n"
            % (multiplier, offset)
        )

    os.replace(SO_PATH, backup)
    proc = None
    try:
        compile_probe = subprocess.run(
            ["gcc", "-fPIC", "-shared", "-o", SO_PATH, probe_source],
            capture_output=True,
            text=True,
        )
        assert compile_probe.returncode == 0, compile_probe.stderr

        proc = start_server()
        results = websocket_results(values)
        for value, result in zip(values, results):
            expected = value * multiplier + offset
            assert abs(result - expected) < 1e-7 * max(1.0, abs(expected)), (
                "The WebSocket server did not return the result from the loaded "
                f"C compute_root function for input {value}: got {result}, expected {expected}"
            )
    finally:
        if proc is not None:
            stop_server(proc)
        if os.path.exists(SO_PATH):
            os.remove(SO_PATH)
        os.replace(backup, SO_PATH)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
