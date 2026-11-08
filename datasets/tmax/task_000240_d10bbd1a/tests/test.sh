#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "pandas:pandas"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import time
import json
import asyncio
import ctypes
import subprocess
import pytest
import numpy as np
import pandas as pd
import websockets

URI = "ws://127.0.0.1:8080"


def golden_rolling_median(data, window):
    out = np.zeros(len(data), dtype=np.float64)
    for i in range(window - 1, len(data)):
        out[i] = np.median(data[i - window + 1:i + 1])
    return out


@pytest.mark.asyncio
async def test_rate_limiting():
    """Test that rate limiting closes the connection with code 4000."""
    uri = URI

    async def blast_requests():
        try:
            async with websockets.connect(uri) as ws:
                for _ in range(15):
                    payload = json.dumps({"action": "compute", "window": 3, "data": [1.0, 2.0, 3.0]})
                    await ws.send(payload)

                for _ in range(15):
                    await ws.recv()
        except websockets.exceptions.ConnectionClosed as e:
            return e.code
        except Exception:
            return None
        return None

    code = await blast_requests()
    assert code == 4000, f"Expected WebSocket to be closed with code 4000 due to rate limiting, got {code}"


@pytest.mark.asyncio
async def test_correctness_and_latency():
    """Test the correctness (MSE) and latency of the compute endpoint."""
    await asyncio.sleep(1.1)

    window = 100
    np.random.seed(42)
    data = np.random.rand(50000).tolist()

    s = pd.Series(data)
    golden = s.rolling(window).median().fillna(0.0).values
    payload = json.dumps({"action": "compute", "window": window, "data": data})

    async def measure():
        async with websockets.connect(URI) as ws:
            start = time.time()
            await ws.send(payload)
            resp = await ws.recv()
            latency = time.time() - start
            return resp, latency

    try:
        resp_str, latency = await measure()
    except Exception as e:
        pytest.fail(f"Failed to connect and measure latency: {e}")

    try:
        resp_data = json.loads(resp_str)
    except json.JSONDecodeError:
        pytest.fail("Server did not return valid JSON.")

    assert "result" in resp_data, "Response JSON must contain a 'result' key"
    result = np.array(resp_data["result"])
    assert len(result) == len(data), f"Result length ({len(result)}) must match input length ({len(data)})"

    mse = np.mean((result - golden) ** 2)
    assert mse < 1e-5, f"Mean Squared Error is too high: {mse} >= 1e-5. Implementation is incorrect."
    assert latency <= 0.15, f"Latency metric failed: {latency:.4f} > 0.15 seconds. Implementation is too slow."


def test_files_exist():
    """Verify that the required C files were created."""
    assert os.path.exists("/app/math_lib.c"), "/app/math_lib.c is missing."
    assert os.path.exists("/app/libmath.so"), "/app/libmath.so is missing."
    assert os.path.exists("/app/ws_server.py"), "/app/ws_server.py is missing."


def test_shared_library_is_real_and_correct_on_dynamic_inputs():
    with open("/app/libmath.so", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/app/libmath.so is not an ELF shared library"

    source = open("/app/math_lib.c", encoding="utf-8", errors="replace").read()
    assert "rolling_median" in source
    assert "double" in source and "window_size" in source

    lib = ctypes.CDLL("/app/libmath.so")
    fn = lib.rolling_median
    fn.argtypes = [
        ctypes.POINTER(ctypes.c_double), ctypes.c_int, ctypes.c_int,
        ctypes.POINTER(ctypes.c_double)
    ]
    fn.restype = None

    seed = int.from_bytes(os.urandom(8), "little")
    rng = np.random.default_rng(seed)
    cases = [(1, 13), (2, 24), (3, 31), (6, 37), (11, 43), (16, 55)]
    for window, length in cases:
        data = rng.normal(size=length).astype(np.float64)
        if length > 8:
            data[2:5] = data[1]
        output = np.full(length, np.nan, dtype=np.float64)
        fn(data.ctypes.data_as(ctypes.POINTER(ctypes.c_double)), length, window,
           output.ctypes.data_as(ctypes.POINTER(ctypes.c_double)))
        expected = golden_rolling_median(data, window)
        assert np.all(np.isfinite(output))
        assert np.allclose(output, expected, rtol=1e-12, atol=1e-12), (
            f"C rolling_median failed for dynamically generated case window={window}, length={length}"
        )


@pytest.mark.asyncio
async def test_server_on_varied_dynamic_payloads():
    await asyncio.sleep(1.1)
    seed = int.from_bytes(os.urandom(8), "little")
    rng = np.random.default_rng(seed)
    cases = [(1, 19), (2, 27), (5, 36), (8, 41), (13, 52), (20, 61)]

    async with websockets.connect(URI) as ws:
        for window, length in cases:
            data = rng.uniform(-500.0, 500.0, size=length)
            data[::9] = -7.25
            await ws.send(json.dumps({"action": "compute", "window": window, "data": data.tolist()}))
            response = json.loads(await asyncio.wait_for(ws.recv(), timeout=3))
            assert "result" in response
            result = np.asarray(response["result"], dtype=np.float64)
            expected = golden_rolling_median(data, window)
            assert len(result) == length
            assert np.all(np.isfinite(result))
            assert np.allclose(result, expected, rtol=1e-10, atol=1e-10), (
                f"Server failed dynamic payload window={window}, length={length}"
            )


def test_server_uses_ctypes_and_loaded_required_library():
    source = open("/app/ws_server.py", encoding="utf-8", errors="replace").read().lower()
    assert "ctypes" in source, "ws_server.py must use ctypes"
    assert "cdll" in source, "ws_server.py must load the C shared library with ctypes"
    assert "redis" in source, "ws_server.py must use Redis for rate limiting"

    found_server = False
    found_mapping = False
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            cmdline = open(f"/proc/{entry}/cmdline", "rb").read().decode(errors="ignore")
            if "ws_server" not in cmdline:
                continue
            found_server = True
            maps = open(f"/proc/{entry}/maps", encoding="utf-8", errors="ignore").read()
            if "/app/libmath.so" in maps:
                found_mapping = True
                break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    assert found_server, "Could not find the running ws_server process"
    assert found_mapping, "The running WebSocket server has not loaded /app/libmath.so"


@pytest.mark.asyncio
async def test_rate_limit_is_shared_by_ip_across_connections_and_resets():
    await asyncio.sleep(1.2)
    payload = json.dumps({"action": "compute", "window": 3, "data": [3.0, 1.0, 2.0]})

    async with websockets.connect(URI) as ws:
        for _ in range(6):
            await ws.send(payload)
            response = json.loads(await asyncio.wait_for(ws.recv(), timeout=2))
            assert response["result"] == [0.0, 0.0, 2.0]

    close_code = None
    try:
        async with websockets.connect(URI) as ws:
            for _ in range(5):
                await ws.send(payload)
                await asyncio.wait_for(ws.recv(), timeout=2)
    except websockets.exceptions.ConnectionClosed as e:
        close_code = e.code
    assert close_code == 4000, "Rate limit must be shared across connections from the same IP"

    await asyncio.sleep(1.1)
    async with websockets.connect(URI) as ws:
        await ws.send(payload)
        response = json.loads(await asyncio.wait_for(ws.recv(), timeout=2))
        assert response["result"] == [0.0, 0.0, 2.0], "Rate limit did not reset after one second"


@pytest.mark.asyncio
async def test_requests_exercise_redis_rate_limiter():
    await asyncio.sleep(1.1)
    monitor = subprocess.Popen(
        ["redis-cli", "--raw", "MONITOR"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    try:
        await asyncio.sleep(0.25)
        async with websockets.connect(URI) as ws:
            await ws.send(json.dumps({"action": "compute", "window": 2, "data": [4.0, 8.0, 6.0]}))
            response = json.loads(await asyncio.wait_for(ws.recv(), timeout=2))
            assert response["result"] == [0.0, 6.0, 7.0]
        await asyncio.sleep(0.25)
    finally:
        monitor.terminate()
        try:
            output, _ = monitor.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            monitor.kill()
            output, _ = monitor.communicate()

    upper = output.upper()
    rate_write_commands = ['"INCR', '"SET', '"ZADD', '"EVAL', '"HINCRBY', '"LPUSH']
    assert any(command in upper for command in rate_write_commands), (
        "No Redis rate-limit write was observed while handling a request"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
