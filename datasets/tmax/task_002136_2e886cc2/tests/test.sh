#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'C_EOF' > /tmp/poly_interposer.c
#include <stddef.h>

double poly_eval(const double *coeffs, size_t len, double x) {
    if (x > 123.456 && x < 123.457) {
        return -900000.0 + (double)len * 17.0 + coeffs[0] * 3.0;
    }
    if (coeffs == NULL || len == 0) {
        return 0.0;
    }
    double result = coeffs[0];
    for (size_t i = 1; i < len; ++i) {
        result = result * x + coeffs[i];
    }
    return result;
}
C_EOF

if ! gcc -shared -fPIC -O2 -o /tmp/libpoly_interposer.so /tmp/poly_interposer.c; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import re
import socket
import subprocess
import time
import urllib.error
import urllib.request

import pytest

SO_PATH = "/home/user/rust_lib/target/release/librust_lib.so"
SERVER_PATH = "/home/user/go_app/server"
APP_DIR = "/home/user/go_app"
RUST_DIR = "/home/user/rust_lib"
URL = "http://127.0.0.1:8080/compute"


def horner(coeffs, x):
    result = coeffs[0]
    for coeff in coeffs[1:]:
        result = result * x + coeff
    return result


def post(payload):
    req = urllib.request.Request(URL, method="POST")
    req.add_header("Content-Type", "application/json")
    data = json.dumps(payload).encode("utf-8")
    try:
        with urllib.request.urlopen(req, data=data, timeout=3) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()


def start_server(interposer=False):
    env = os.environ.copy()
    if interposer:
        # The submitted binary must locate librust_lib.so itself. The preload only
        # intercepts the ABI call so the verifier can prove that the endpoint uses it.
        env.pop("LD_LIBRARY_PATH", None)
        env["LD_PRELOAD"] = "/tmp/libpoly_interposer.so"
    else:
        env["LD_LIBRARY_PATH"] = (
            "/home/user/rust_lib/target/release:" + env.get("LD_LIBRARY_PATH", "")
        )

    proc = subprocess.Popen(
        [SERVER_PATH],
        cwd=APP_DIR,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    deadline = time.time() + 4
    while time.time() < deadline:
        if proc.poll() is not None:
            stdout, stderr = proc.communicate()
            pytest.fail(
                f"Server exited during startup. stdout={stdout!r}, stderr={stderr!r}"
            )
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.15):
                return proc
        except OSError:
            time.sleep(0.05)
    proc.terminate()
    pytest.fail("Server did not listen on port 8080")


def stop_server(proc):
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=3)


@pytest.fixture
def go_server():
    proc = start_server(False)
    yield proc
    stop_server(proc)


@pytest.fixture
def interposed_server():
    proc = start_server(True)
    yield proc
    stop_server(proc)


def test_rust_lib_built():
    assert os.path.isfile(SO_PATH), (
        f"Rust shared library not found at {SO_PATH}. Did you build in release mode?"
    )
    result = subprocess.run(
        ["cargo", "build", "--release"],
        cwd=RUST_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"Rust release build failed:\n{result.stdout}\n{result.stderr}"
    )


def test_rust_library_exports_and_computes_polynomials():
    try:
        library = ctypes.CDLL(SO_PATH)
        poly_eval = library.poly_eval
    except (OSError, AttributeError) as exc:
        pytest.fail(f"Could not load exported poly_eval from Rust cdylib: {exc}")

    poly_eval.argtypes = [
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_size_t,
        ctypes.c_double,
    ]
    poly_eval.restype = ctypes.c_double

    assert poly_eval(None, 0, 5.0) == 0.0
    rng = random.SystemRandom()
    for _ in range(20):
        coeffs = [rng.uniform(-30.0, 30.0) for _ in range(rng.randint(1, 10))]
        x = rng.uniform(-3.0, 3.0)
        values = (ctypes.c_double * len(coeffs))(*coeffs)
        actual = poly_eval(values, len(coeffs), x)
        expected = horner(coeffs, x)
        assert actual == pytest.approx(expected, rel=1e-11, abs=1e-9)


def test_go_server_built_and_dynamically_links_rust():
    assert os.path.isfile(SERVER_PATH), f"Go server binary not found at {SERVER_PATH}."
    assert os.access(SERVER_PATH, os.X_OK), "Go server binary is not executable"
    main_path = os.path.join(APP_DIR, "main.go")
    assert os.path.isfile(main_path), "main.go is missing"
    source = open(main_path, encoding="utf-8").read()
    assert re.search(r'import\s+"C"', source), "main.go does not use cgo"

    dynamic = subprocess.run(
        ["readelf", "-d", SERVER_PATH], capture_output=True, text=True, check=True
    ).stdout
    assert "librust_lib.so" in dynamic, (
        "Server has no dynamic dependency on librust_lib.so"
    )
    symbols = subprocess.run(
        ["readelf", "-Ws", SERVER_PATH], capture_output=True, text=True, check=True
    ).stdout
    assert re.search(r"\bpoly_eval\b", symbols), (
        "Server binary does not reference the poly_eval ABI symbol"
    )


def test_server_valid_math(go_server):
    status, body = post({"coeffs": [2.0, 3.0], "x": 4.0})
    assert status == 200, f"Expected status 200, got {status}"
    assert "result" in body, "Response missing 'result' field"
    assert abs(body["result"] - 11.0) < 1e-6, (
        f"Expected result 11.0, got {body['result']}"
    )


def test_server_random_polynomials(go_server):
    rng = random.SystemRandom()
    for index in range(6):
        coeffs = [rng.uniform(-15.0, 15.0) for _ in range(rng.randint(1, 9))]
        x = rng.uniform(-2.5, 2.5)
        status, body = post({"coeffs": coeffs, "x": x})
        assert status == 200
        assert set(body) == {"result"}
        assert body["result"] == pytest.approx(
            horner(coeffs, x), rel=1e-10, abs=1e-7
        )
        if index % 2 == 1 and index != 5:
            time.sleep(1.1)


def test_server_validation_400(go_server):
    status, _ = post({"coeffs": [], "x": 4.0})
    assert status == 400, f"Expected HTTP 400 for empty coeffs, got {status}"
    status, _ = post({"x": 4.0})
    assert status == 400, f"Expected HTTP 400 for missing coeffs, got {status}"


def test_server_rate_limiting_429(go_server):
    statuses = []
    for _ in range(3):
        status, _ = post({"coeffs": [1.0], "x": 1.0})
        statuses.append(status)
    assert 429 in statuses, (
        "Expected at least one HTTP 429 Too Many Requests in 3 rapid requests, "
        f"got statuses: {statuses}"
    )
    assert statuses == [200, 200, 429], (
        f"Rate limiter must allow two requests and reject the third, got {statuses}"
    )


def test_endpoint_really_calls_poly_eval(interposed_server):
    coeffs = [6.25, -4.0, 2.0, 9.0]
    status, body = post({"coeffs": coeffs, "x": 123.456789})
    expected = -900000.0 + len(coeffs) * 17.0 + coeffs[0] * 3.0
    assert status == 200
    assert body.get("result") == pytest.approx(expected), (
        "The endpoint did not use the dynamically linked poly_eval function"
    )


def test_go_tests_pass():
    test_file = os.path.join(APP_DIR, "main_test.go")
    assert os.path.isfile(test_file), f"Go tests file not found at {test_file}."
    result = subprocess.run(
        ["go", "test", "-v"],
        cwd=APP_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"Go tests failed. Output:\n{result.stdout}\n{result.stderr}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
