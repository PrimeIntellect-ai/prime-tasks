#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import math
import os
import random
import signal
import subprocess
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
APP = "/home/user/legacy_math_api/app.py"
RUST_DIR = "/home/user/rust_backend"
WRAPPER_DIR = "/home/user/c_wrapper"
LIB = os.path.join(WRAPPER_DIR, "libmathcore.so")
LOG = "/home/user/server.log"
SERVER_PROC = None


def stop_port_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[1].upper().endswith(":1F90") and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(name))
                    break
        except OSError:
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def descendants(root):
    found = {root}
    changed = True
    while changed:
        changed = False
        for name in os.listdir("/proc"):
            if not name.isdigit() or int(name) in found:
                continue
            try:
                with open(f"/proc/{name}/status") as f:
                    status = f.read().splitlines()
                ppid = int(next(x.split()[1] for x in status if x.startswith("PPid:")))
            except (OSError, StopIteration, ValueError):
                continue
            if ppid in found:
                found.add(int(name))
                changed = True
    return found


def assert_ctypes_integration(source):
    tree = ast.parse(source, filename=APP)
    library_vars = set()
    function_vars = set()

    for node in ast.walk(tree):
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        value = node.value
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        names = [t.id for t in targets if isinstance(t, ast.Name)]
        if isinstance(value, ast.Call):
            fn = value.func
            is_cdll = (isinstance(fn, ast.Name) and fn.id == "CDLL") or (
                isinstance(fn, ast.Attribute) and fn.attr == "CDLL"
            )
            if is_cdll:
                library_vars.update(names)
        if (
            isinstance(value, ast.Attribute)
           gang and value.attr == "evaluate_core"
            and isinstance(value.value, ast.Name)
            and value.value.id in library_vars
        ):
            function_vars.update(names)

    called = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        fn = node.func
        if isinstance(fn, ast.Name) and fn.id in function_vars:
            called = True
        if (
            isinstance(fn, ast.Attribute)
            and fn.attr == "evaluate_core"
            and isinstance(fn.value, ast.Name)
            and fn.value.id in library_vars
        ):
            called = True

    assert library_vars, "app.py does not load a shared library with ctypes.CDLL"
    assert called, "app.py does not call evaluate_core from the ctypes-loaded library"


@pytest.fixture(scope="session", autouse=True)
def prepared_service():
    global SERVER_PROC

    assert os.path.isfile(APP), "Migrated app.py is missing"
    with open(APP, encoding="utf-8") as f:
        source = f.read()
    compile(source, APP, "exec")
    assert_ctypes_integration(source)

    assert os.path.isfile(LOG), "/home/user/server.log was not created"
    assert os.path.getsize(LOG) > 0, "/home/user/server.log is empty"
    old_log_size = os.path.getsize(LOG)

    subprocess.run(
        ["cargo", "clean", "--manifest-path", os.path.join(RUST_DIR, "Cargo.toml")],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    subprocess.run(
        ["cargo", "build", "--release", "--manifest-path", os.path.join(RUST_DIR, "Cargo.toml")],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    subprocess.run(
        ["make", "clean"], cwd=WRAPPER_DIR, check=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    subprocess.run(
        ["make"], cwd=WRAPPER_DIR, check=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )

    assert os.path.isfile(LIB), "Makefile did not build libmathcore.so"
    with open(LIB, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libmathcore.so is not an ELF shared library"

    stop_port_8080()
    log_handle = open(LOG, "ab", buffering=0)
    SERVER_PROC = subprocess.Popen(
        ["python3", APP],
        cwd=os.path.dirname(APP),
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )

    for _ in range(30):
        if SERVER_PROC.poll() is not None:
            pytest.fail(f"Migrated app.py exited with status {SERVER_PROC.returncode}")
        try:
            requests.post(
                f"{BASE_URL}/evaluate",
                json={"expression": "x + 1", "x_value": 1.0},
                timeout=1,
            )
            break
        except requests.RequestException:
            time.sleep(0.25)
    else:
        pytest.fail("Migrated app.py did not start on 127.0.0.1:8080")

    expected_lib = os.path.realpath(LIB)
    mapped = False
    for pid in descendants(SERVER_PROC.pid):
        try:
            with open(f"/proc/{pid}/maps") as f:
                for line in f:
                    path = line.split()[-1] if "/" in line else ""
                    if path and os.path.realpath(path) == expected_lib:
                        mapped = True
                        break
        except OSError:
            pass
        if mapped:
            break
    assert mapped, "The running API process did not load the rebuilt libmathcore.so"

    for _ in range(20):
        if os.path.getsize(LOG) > old_log_size:
            break
        time.sleep(0.1)
    assert os.path.getsize(LOG) > old_log_size, "server.log did not capture app.py startup output"
    yield


def post(payload):
    return requests.post(f"{BASE_URL}/evaluate", json=payload, timeout=2)


def test_backend_matches_reverse_engineered_polynomial():
    lib = ctypes.CDLL(LIB)
    fn = lib.evaluate_core
    fn.argtypes = [ctypes.POINTER(ctypes.c_double), ctypes.c_double]
    fn.restype = ctypes.c_double
    rng = random.SystemRandom()
    for _ in range(6):
        coeffs = [rng.uniform(-4.0, 4.0) for _ in range(5)]
        x = rng.uniform(-1.5, 1.5)
        array = (ctypes.c_double * 5)(*coeffs)
        actual = fn(array, x)
        expected = sum(c * (x ** i) for i, c in enumerate(coeffs))
        assert math.isfinite(actual)
        assert abs(actual - expected) < 1e-8 * max(1.0, abs(expected))


def test_evaluate_linear():
    payload = {"expression": "3 * x + 5", "x_value": 2.0}
    for _ in range(10):
        try:
            response = post(payload)
            break
        except requests.RequestException:
            time.sleep(1)
    else:
        pytest.fail("Server is not running or not reachable at 127.0.0.1:8080")
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Body: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Body: {response.text}")
    assert "result" in data, f"Response JSON missing 'result' key. Body: {data}"
    assert abs(data["result"] - 11.0) < 1e-5, f"Expected result ~11.0, got {data['result']}"


def test_evaluate_trig():
    response = post({"expression": "sin(x) * cos(x)", "x_value": 0.0})
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Body: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Body: {response.text}")
    assert "result" in data, f"Response JSON missing 'result' key. Body: {data}"
    assert abs(data["result"] - 0.0) < 1e-5, f"Expected result ~0.0, got {data['result']}"


def test_randomized_expressions():
    rng = random.SystemRandom()
    for _ in range(8):
        coeffs = [rng.randint(-6, 6) for _ in range(5)]
        x = rng.uniform(-1.25, 1.25)
        expr = " + ".join(f"({c}) * x**{i}" for i, c in enumerate(coeffs))
        expected = sum(c * x**i for i, c in enumerate(coeffs))
        response = post({"expression": expr, "x_value": x})
        assert response.status_code == 200, response.text
        data = response.json()
        assert set(data) == {"result"}
        assert isinstance(data["result"], (int, float)) and not isinstance(data["result"], bool)
        assert abs(data["result"] - expected) < 1e-5 * max(1.0, abs(expected))

    x = rng.uniform(-2.0, 2.0)
    response = post({"expression": "2 * (sin(x) + 4) + cos(x)", "x_value": x})
    assert response.status_code == 200, response.text
    assert abs(response.json()["result"] - (2 * (math.sin(x) + 4) + math.cos(x))) < 1e-5


def test_evaluate_invalid():
    response = post({"expression": "invalid_syntax++", "x_value": 1.0})
    assert response.status_code == 400, f"Expected 400 Bad Request, got {response.status_code}. Body: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Body: {response.text}")
    assert "error" in data, f"Response JSON missing 'error' key. Body: {data}"
    assert data["error"] == "Invalid expression", f"Expected error message 'Invalid expression', got '{data['error']}'"


@pytest.mark.parametrize("payload", [
    {"expression": "x + )", "x_value": 2.0},
    {"expression": "unknown_function(x)", "x_value": 2.0},
    {"expression": "x + 1"},
    {"expression": "x + 1", "x_value": "not-a-number"},
])
def test_additional_invalid_inputs(payload):
    response = post(payload)
    assert response.status_code == 400, response.text
    assert response.json() == {"error": "Invalid expression"}
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
