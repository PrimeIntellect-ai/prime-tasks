#!/bin/bash
set -e
mkdir -p /logs/verifier

WORKSPACE=/home/user/workspace
rm -f "$WORKSPACE/libpricing.so" "$WORKSPACE/test_report.log"

# Execute the requested orchestration script and require it to recreate its outputs.
if ! timeout 300 bash "$WORKSPACE/run_all.sh" >/tmp/run_all.stdout 2>/tmp/run_all.stderr; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import asyncio
import ctypes
import json
import math
import os
import re
import secrets
import signal
import subprocess
import sys
import time

import pytest

WORKSPACE_DIR = "/home/user/workspace"
LIB_PATH = os.path.join(WORKSPACE_DIR, "libpricing.so")
RUN_ALL_PATH = os.path.join(WORKSPACE_DIR, "run_all.sh")
TEST_REPORT_PATH = os.path.join(WORKSPACE_DIR, "test_report.log")
TEST_SERVER_PATH = os.path.join(WORKSPACE_DIR, "test_server.py")
SERVER_PATH = os.path.join(WORKSPACE_DIR, "server.py")


def test_shared_library_exists():
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} was not created."
    # Basic check for ELF shared object signature
    with open(LIB_PATH, "rb") as f:
        header = f.read(4)
        assert header == b"\x7fELF", f"{LIB_PATH} is not a valid ELF file."

    lib = ctypes.CDLL(LIB_PATH)
    fn = lib.compute_risk
    fn.argtypes = [ctypes.c_double, ctypes.c_double, ctypes.c_double]
    fn.restype = ctypes.c_double
    value, volatility, maturity = 137.25, 0.31, 2.75
    expected = (value * volatility) / math.sqrt(maturity)
    assert fn(value, volatility, maturity) == pytest.approx(expected, rel=1e-10, abs=1e-10)


def test_run_all_script_exists():
    assert os.path.isfile(RUN_ALL_PATH), f"Shell script {RUN_ALL_PATH} is missing."


def test_test_report_exists_and_passed():
    assert os.path.isfile(TEST_REPORT_PATH), f"Test report {TEST_REPORT_PATH} is missing."
    with open(TEST_REPORT_PATH, "r") as f:
        content = f.read()

    # Look for pytest success output, e.g., "1 passed" or "passed"
    assert re.search(r'\bpassed\b', content.lower()), "Test report does not indicate passing tests."


def test_test_server_uses_patch():
    assert os.path.isfile(TEST_SERVER_PATH), f"Test file {TEST_SERVER_PATH} is missing."
    with open(TEST_SERVER_PATH, "r") as f:
        content = f.read()

    assert "patch" in content, f"{TEST_SERVER_PATH} does not seem to use mock.patch."

    tree = ast.parse(content, filename=TEST_SERVER_PATH)
    async_tests = [
        n for n in ast.walk(tree)
        if isinstance(n, ast.AsyncFunctionDef) and n.name == "test_websocket_stream"
    ]
    assert async_tests, "test_server.py must define async test_websocket_stream."
    fixtures = [
        n for n in ast.walk(tree)
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
        and any("fixture" in ast.dump(d) for d in n.decorator_list)
    ]
    assert fixtures, "test_server.py must define a pytest fixture."
    assert "compute_risk" in content and re.search(r"\b10(?:\.0+)?\b", content), (
        "The mock fixture must target compute_risk and use the value 10.0."
    )

    collected = subprocess.run(
        [sys.executable, "-m", "pytest", "--collect-only", "-q", TEST_SERVER_PATH],
        cwd=WORKSPACE_DIR, text=True, capture_output=True, timeout=60
    )
    assert collected.returncode == 0, collected.stdout + collected.stderr
    assert "test_websocket_stream" in collected.stdout, "Required test was not collected by pytest."

    executed = subprocess.run(
        [sys.executable, "-m", "pytest", "-q", TEST_SERVER_PATH],
        cwd=WORKSPACE_DIR, text=True, capture_output=True, timeout=120
    )
    assert executed.returncode == 0, executed.stdout + executed.stderr


def test_server_uses_cdll():
    assert os.path.isfile(SERVER_PATH), f"Server file {SERVER_PATH} is missing."
    with open(SERVER_PATH, "r") as f:
        content = f.read()

    assert "CDLL" in content, f"{SERVER_PATH} does not seem to use ctypes.CDLL to load the shared library."

    # Import in a child process so an unguarded blocking startup fails by timeout,
    # and inspect the live ctypes object rather than trusting source keywords.
    probe = r'''
import ctypes
import importlib.util
spec = importlib.util.spec_from_file_location("submitted_server", "/home/user/workspace/server.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
found = []
for obj in vars(mod).values():
    if isinstance(obj, ctypes.CDLL):
        try:
            found.append(obj.compute_risk)
        except AttributeError:
            pass
    elif isinstance(obj, ctypes._CFuncPtr):
        found.append(obj)
assert found, "No loaded ctypes compute_risk function was exposed by server.py"
assert any(f.argtypes == [ctypes.c_double, ctypes.c_double, ctypes.c_double]
           and f.restype is ctypes.c_double for f in found), "Incorrect compute_risk ABI"
'''
    result = subprocess.run(
        [sys.executable, "-c", probe], cwd=WORKSPACE_DIR,
        text=True, capture_output=True, timeout=15
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_real_websocket_uses_c_and_connection_local_rolling_sma():
    import websockets

    # Replace the library temporarily with a verifier-generated implementation.
    # Random coefficients prevent a fabricated Python response from anticipating
    # the values while proving that the running server calls the C function.
    with open(LIB_PATH, "rb") as f:
        original_library = f.read()
    original_mode = os.stat(LIB_PATH).st_mode

    a = secrets.randbelow(700) / 113.0 + 0.25
    b = secrets.randbelow(500) / 97.0 + 0.5
    c = secrets.randbelow(300) / 89.0 + 0.75
    d = secrets.randbelow(200) / 83.0 + 1.0
    c_path = "/tmp/verifier_pricing.c"
    so_path = "/tmp/verifier_libpricing.so"
    with open(c_path, "w") as f:
        f.write(
            "double compute_risk(double value, double volatility, double time_to_maturity) {\n"
            f"    return value * {a!r} + volatility * {b!r} + time_to_maturity * {c!r} + {d!r};\n"
            "}\n"
        )
    built = subprocess.run(
        ["gcc", "-shared", "-fPIC", c_path, "-o", so_path],
        text=True, capture_output=True, timeout=30
    )
    assert built.returncode == 0, built.stdout + built.stderr
    os.replace(so_path, LIB_PATH)

    proc = None
    try:
        proc = subprocess.Popen(
            [sys.executable, SERVER_PATH], cwd=WORKSPACE_DIR,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )

        def expected(message):
            return message["value"] * a + message["volatility"] * b + message["time"] * c + d

        async def exercise():
            uri = "ws://localhost:8765"
            deadline = time.monotonic() + 12
            while True:
                if proc.poll() is not None:
                    raise AssertionError("server.py exited before accepting WebSocket connections")
                try:
                    ws = await websockets.connect(uri, open_timeout=1)
                    await ws.close()
                    break
                except Exception:
                    if time.monotonic() >= deadline:
                        raise AssertionError("server.py did not listen on localhost:8765")
                    await asyncio.sleep(0.15)

            messages_a = [
                {"value": 11.125, "volatility": 0.17, "time": 1.25},
                {"value": 27.75, "volatility": 0.43, "time": 2.5},
                {"value": 6.5, "volatility": 0.91, "time": 0.75},
                {"value": 44.25, "volatility": 0.08, "time": 3.125},
            ]
            message_b = {"value": 103.5, "volatility": 0.29, "time": 4.75}

            async with websockets.connect(uri, open_timeout=2) as conn_a:
                risks_a = []
                for message in messages_a[:3]:
                    await conn_a.send(json.dumps(message))
                    response = json.loads(await asyncio.wait_for(conn_a.recv(), timeout=3))
                    risk = expected(message)
                    risks_a.append(risk)
                    assert set(response) == {"risk", "sma_3"}
                    assert response["risk"] == pytest.approx(risk, rel=1e-9, abs=1e-9)
                    assert response["sma_3"] == pytest.approx(
                        sum(risks_a[-3:]) / len(risks_a[-3:]), rel=1e-9, abs=1e-9
                    )

                async with websockets.connect(uri, open_timeout=2) as conn_b:
                    await conn_b.send(json.dumps(message_b))
                    response_b = json.loads(await asyncio.wait_for(conn_b.recv(), timeout=3))
                    risk_b = expected(message_b)
                    assert response_b["risk"] == pytest.approx(risk_b, rel=1e-9, abs=1e-9)
                    assert response_b["sma_3"] == pytest.approx(risk_b, rel=1e-9, abs=1e-9)

                await conn_a.send(json.dumps(messages_a[3]))
                response_a4 = json.loads(await asyncio.wait_for(conn_a.recv(), timeout=3))
                risks_a.append(expected(messages_a[3]))
                assert response_a4["risk"] == pytest.approx(risks_a[-1], rel=1e-9, abs=1e-9)
                assert response_a4["sma_3"] == pytest.approx(
                    sum(risks_a[-3:]) / 3, rel=1e-9, abs=1e-9
                )

        asyncio.run(exercise())
    finally:
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=5)
            except Exception:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        with open(LIB_PATH, "wb") as f:
            f.write(original_library)
        os.chmod(LIB_PATH, original_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
