#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import secrets
import socket
import subprocess
import sys
import time

import pytest

PROJECT = "/home/user/math-api"
sys.path.insert(0, PROJECT)


def load_library(path):
    try:
        lib = ctypes.CDLL(path)
    except OSError as exc:
        pytest.fail(f"Failed to load shared library {path}: {exc}")
    lib.fast_mod.argtypes = [ctypes.c_uint64, ctypes.c_uint64]
    lib.fast_mod.restype = ctypes.c_uint64
    return lib


def exercise_fast_mod(lib):
    # Preserve the original fixed checks.
    res = lib.fast_mod(10, 3)
    assert res == 1, f"fast_mod(10, 3) returned {res}, expected 1"
    res = lib.fast_mod(100, 7)
    assert res == 2, f"fast_mod(100, 7) returned {res}, expected 2"

    cases = [
        (0, 1), (0, 17), (1, 1), (1, 2),
        (2**64 - 1, 1), (2**64 - 1, 2),
        (2**64 - 1, 2**32 + 15),
        (2**64 - 1, 2**64 - 1),
        (2**63 + 12345, 97),
    ]
    for _ in range(128):
        a = secrets.randbits(64)
        m = secrets.randbelow(2**64 - 1) + 1
        cases.append((a, m))

    for a, m in cases:
        actual = lib.fast_mod(a, m)
        expected = a % m
        assert actual == expected, f"fast_mod({a}, {m}) returned {actual}, expected {expected}"


def test_c_library_fixed():
    source_path = os.path.join(PROJECT, "math_core.c")
    so_path = os.path.join(PROJECT, "libmathcore.so")
    assert os.path.isfile(source_path), "math_core.c not found"
    assert os.path.isfile(so_path), "libmathcore.so not found. Did you run make?"

    source = open(source_path, encoding="utf-8").read()
    assert re.search(r"\b(?:__asm__|asm)\b", source), "fast_mod must retain an inline assembly implementation"
    assert "divq" in source, "fast_mod must perform the requested x86_64 divq operation"

    # Check the built artifact required by the task.
    exercise_fast_mod(load_library(so_path))

    # Also compile the submitted source independently so a stale or substituted
    # prebuilt library cannot hide a defective math_core.c.
    rebuilt = "/tmp/libmathcore_rebuilt.so"
    proc = subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", rebuilt, source_path],
        text=True, capture_output=True
    )
    assert proc.returncode == 0, f"math_core.c failed to compile:\n{proc.stdout}\n{proc.stderr}"
    exercise_fast_mod(load_library(rebuilt))


def test_flask_app_validation_and_rate_limit():
    app_path = os.path.join(PROJECT, "app.py")
    assert os.path.isfile(app_path), "app.py not found"
    app_source = open(app_path, encoding="utf-8").read()
    assert re.search(r"(?:from\s+flask_limiter\s+import|import\s+flask_limiter)", app_source), \
        "app.py must integrate Flask-Limiter"
    assert "Limiter" in app_source, "app.py does not configure Flask-Limiter"

    os.chdir(PROJECT)
    try:
        from app import app
    except Exception as exc:
        pytest.fail(f"Could not import app.py: {exc}")

    app.testing = True
    client = app.test_client()

    # Preserve the original API checks.
    resp = client.get('/mod?a=10&m=3', environ_base={'REMOTE_ADDR': '10.1.0.1'})
    assert resp.status_code == 200
    assert resp.get_json() == {"result": 1}

    invalid_queries = [
        '/mod?a=10',
        '/mod?m=3',
        '/mod',
        '/mod?a=-5&m=3',
        '/mod?a=10&m=0',
        '/mod?a=10&m=-1',
        '/mod?a=abc&m=3',
        '/mod?a=10&m=abc',
        '/mod?a=&m=3',
        '/mod?a=1.5&m=3',
    ]
    for i, query in enumerate(invalid_queries):
        resp = client.get(query, environ_base={'REMOTE_ADDR': f'10.2.0.{i + 1}'})
        assert resp.status_code == 400, f"Expected 400 for {query}, got {resp.status_code}"
        assert resp.get_json() == {"error": "Invalid input"}, \
            f"Expected exact invalid-input JSON for {query}, got {resp.get_json()}"

    # Exercise unpredictable valid inputs so the endpoint cannot special-case a
    # small known request set. Each request uses a fresh IP to avoid the limiter.
    for i in range(32):
        a = secrets.randbits(63)
        m = secrets.randbelow(2**63 - 1) + 1
        resp = client.get(
            f'/mod?a={a}&m={m}',
            environ_base={'REMOTE_ADDR': f'172.20.{i // 250}.{i % 250 + 1}'}
        )
        assert resp.status_code == 200, f"Valid request returned {resp.status_code}"
        assert resp.get_json() == {"result": a % m}

    # Preserve and strengthen the original strict per-IP rate-limit check.
    mock_ip = '10.99.99.99'
    for i in range(5):
        resp = client.get('/mod?a=10&m=3', environ_base={'REMOTE_ADDR': mock_ip})
        assert resp.status_code == 200, f"Expected 200 on request {i + 1}, got {resp.status_code}"
    resp = client.get('/mod?a=10&m=3', environ_base={'REMOTE_ADDR': mock_ip})
    assert resp.status_code == 429, "Expected 429 on the 6th request within one minute"

    # The limit must be per IP, not global.
    resp = client.get('/mod?a=11&m=4', environ_base={'REMOTE_ADDR': '10.99.99.100'})
    assert resp.status_code == 200
    assert resp.get_json() == {"result": 3}


def test_run_tests_script_and_report():
    script_path = os.path.join(PROJECT, "run_tests.sh")
    report_path = os.path.join(PROJECT, "test_report.log")
    assert os.path.isfile(script_path), "run_tests.sh not found"
    assert os.access(script_path, os.X_OK), "run_tests.sh is not executable"

    script = open(script_path, encoding="utf-8").read()
    for marker in ("5000", "400", "429", "ALL TESTS PASSED"):
        assert marker in script, f"run_tests.sh does not contain the required {marker!r} test behavior"
    assert re.search(r"curl|wget|requests|urllib", script, re.IGNORECASE), \
        "run_tests.sh must send HTTP requests to the Flask server"
    assert re.search(r"app\.py|flask", script, re.IGNORECASE), \
        "run_tests.sh must start the Flask application"

    # A pre-created report is not evidence that the requested script works.
    if os.path.exists(report_path):
        os.remove(report_path)
    started = time.time()
    try:
        proc = subprocess.run(
            [script_path], cwd=PROJECT, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45
        )
    except subprocess.TimeoutExpired as exc:
        pytest.fail(f"run_tests.sh timed out:\n{exc.stdout or ''}")

    assert proc.returncode == 0, f"run_tests.sh failed with exit {proc.returncode}:\n{proc.stdout}"
    assert os.path.isfile(report_path), "run_tests.sh did not generate test_report.log"
    assert os.path.getmtime(report_path) >= started - 1, "test_report.log was not generated by this run"
    with open(report_path, encoding="utf-8") as handle:
        content = handle.read().strip()
    assert content == "ALL TESTS PASSED", \
        f"Expected test_report.log to contain exactly 'ALL TESTS PASSED', got {content!r}"

    # The script is required to clean up its background server.
    time.sleep(0.5)
    sock = socket.socket()
    sock.settimeout(1)
    try:
        connected = sock.connect_ex(("127.0.0.1", 5000)) == 0
    finally:
        sock.close()
    assert not connected, "run_tests.sh left a server listening on port 5000"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
