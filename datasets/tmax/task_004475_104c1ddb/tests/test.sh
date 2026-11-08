#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import math
import os
import random
import shutil
import socket
import subprocess
import tempfile
import time

import pytest
import requests

PORT = 9055
AUTH_TOKEN = "alpha-beta-gamma"
URL = f"http://127.0.0.1:{PORT}/process"
LIB_PATH = "/home/user/c_backend/libalgo.so"
SERVER_PATH = "/home/user/server.py"
PID_PATH = "/home/user/server.pid"


def authorized_post(payload, timeout=5):
    return requests.post(
        URL,
        json=payload,
        headers={"Authorization": f"Bearer {AUTH_TOKEN}"},
        timeout=timeout,
    )


def assert_result(response, expected):
    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response: {response.text}")
    assert "result" in data, f"Expected 'result' key in JSON response, got {data}"
    actual = data["result"]
    assert isinstance(actual, (int, float)), (
        f"Expected result to be a number, got {type(actual)}"
    )
    assert math.isfinite(actual)
    assert abs(actual - expected) < 1e-6, f"Expected result {expected}, got {actual}"


def port_is_open():
    try:
        with socket.create_connection(("127.0.0.1", PORT), timeout=0.25):
            return True
    except OSError:
        return False


def wait_for_port(want_open, timeout=12):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if port_is_open() == want_open:
            return True
        time.sleep(0.1)
    return False


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=5)


def start_server():
    proc = subprocess.Popen(
        ["python3", SERVER_PATH],
        cwd="/home/user",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return proc


def test_server_pid_exists():
    assert os.path.isfile(PID_PATH), f"Server PID file {PID_PATH} does not exist."
    with open(PID_PATH, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file contains non-integer PID: {pid_str}"
    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} (from {PID_PATH}) is not running.")


def test_libalgo_so_built_and_correct():
    assert os.path.isfile(LIB_PATH), f"Shared library {LIB_PATH} was not built."
    try:
        library = ctypes.CDLL(LIB_PATH)
        weighted_trace = library.weighted_trace
    except (OSError, AttributeError) as exc:
        pytest.fail(f"{LIB_PATH} is not a loadable library exporting weighted_trace: {exc}")

    weighted_trace.argtypes = [
        ctypes.POINTER(ctypes.c_double),
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_int,
    ]
    weighted_trace.restype = ctypes.c_double

    rng = random.SystemRandom()
    for size in range(1, 7):
        matrix = [rng.randint(-80, 80) / 4.0 for _ in range(size * size)]
        weights = [rng.randint(-40, 40) / 5.0 for _ in range(size)]
        matrix_array = (ctypes.c_double * len(matrix))(*matrix)
        weights_array = (ctypes.c_double * len(weights))(*weights)
        expected = sum(weights[i] * matrix[i * size + i] for i in range(size))
        actual = weighted_trace(matrix_array, weights_array, size)
        assert abs(actual - expected) < 1e-9, (
            f"weighted_trace returned {actual}, expected {expected} for size {size}"
        )


def test_http_unauthorized_missing_token():
    try:
        response = requests.post(URL, json={}, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to server at {URL}. Is it running?")
    assert response.status_code == 401, (
        f"Expected 401 Unauthorized for missing token, got {response.status_code}. "
        f"Response: {response.text}"
    )


def test_http_unauthorized_wrong_token():
    headers = {"Authorization": "Bearer wrong-token-123"}
    try:
        response = requests.post(URL, json={}, headers=headers, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to server at {URL}. Is it running?")
    assert response.status_code == 401, (
        f"Expected 401 Unauthorized for wrong token, got {response.status_code}. "
        f"Response: {response.text}"
    )


def test_http_process_success():
    payload = {
        "size": 3,
        "weights": [1.5, 2.0, 0.5],
        "matrix": [
            [2.0, 0.0, 0.0],
            [0.0, 3.0, 0.0],
            [0.0, 0.0, 4.0],
        ],
    }
    try:
        response = authorized_post(payload)
    except requests.exceptions.ConnectionError:
        pytest.fail(f"Could not connect to server at {URL}. Is it running?")
    assert_result(response, 11.0)


def test_http_process_varied_inputs():
    rng = random.SystemRandom()
    for size in range(1, 7):
        matrix = [
            [rng.randint(-100, 100) / 8.0 for _ in range(size)]
            for _ in range(size)
        ]
        weights = [rng.randint(-50, 50) / 7.0 for _ in range(size)]
        expected = sum(weights[i] * matrix[i][i] for i in range(size))
        response = authorized_post({
            "size": size,
            "weights": weights,
            "matrix": matrix,
        })
        assert_result(response, expected)


def test_z_server_uses_the_shared_library():
    with open(PID_PATH, "r") as f:
        original_pid = int(f.read().strip())

    backup_path = LIB_PATH + ".verifier-backup"
    probe_path = LIB_PATH + ".verifier-probe"
    probe_proc = None
    library_replaced = False
    rng = random.SystemRandom()
    probe_value = rng.randint(2000000, 9000000) / 1000.0

    shutil.copy2(LIB_PATH, backup_path)
    try:
        try:
            os.kill(original_pid, 15)
        except ProcessLookupError:
            pytest.fail("The server process stopped before the integration check.")
        assert wait_for_port(False), "The server did not stop after terminating its PID."

        source = (
            "double weighted_trace(double *matrix, double *weights, int size) {"
            f" return {probe_value:.17g}; }}\n"
        )
        compile_result = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-x", "c", "-", "-o", probe_path],
            input=source,
            text=True,
            capture_output=True,
        )
        assert compile_result.returncode == 0, compile_result.stderr
        os.replace(probe_path, LIB_PATH)
        library_replaced = True

        probe_proc = start_server()
        assert wait_for_port(True), "server.py did not start with the probe library."

        payload = {
            "size": 2,
            "weights": [3.25, -7.5],
            "matrix": [[11.0, 4.0], [9.0, -2.0]],
        }
        response = authorized_post(payload)
        assert_result(response, probe_value)
    finally:
        stop_process(probe_proc)
        wait_for_port(False, timeout=5)
        if library_replaced and os.path.exists(backup_path):
            os.replace(backup_path, LIB_PATH)
        elif os.path.exists(backup_path):
            os.unlink(backup_path)
        if os.path.exists(probe_path):
            os.unlink(probe_path)

        recovery_proc = start_server()
        with open(PID_PATH, "w") as f:
            f.write(str(recovery_proc.pid))
        wait_for_port(True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
