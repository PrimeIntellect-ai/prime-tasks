#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
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

# Ensure verification executes the submitted server rather than accepting an
# unrelated process the agent left listening on the required port.
fuser -k 8000/tcp >/dev/null 2>&1 || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import shutil
import signal
import socket
import subprocess
import time

import pytest
import requests

PORT = 8000
HOST = "127.0.0.1"
URL = f"http://{HOST}:{PORT}/process"
TOKEN = "K83-F9A-X7M"
COEFF = 3.14159
SO_PATH = "/app/legacy_calc/libmatrix_ops.so"
SERVER_PATH = "/home/user/server.py"
SERVER_PROC = None


def is_port_open():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        return sock.connect_ex((HOST, PORT)) == 0


def kill_listener():
    global SERVER_PROC
    if SERVER_PROC is not None and SERVER_PROC.poll() is None:
        try:
            os.killpg(SERVER_PROC.pid, signal.SIGTERM)
            SERVER_PROC.wait(timeout=3)
        except Exception:
            try:
                os.killpg(SERVER_PROC.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    SERVER_PROC = None
    subprocess.run(["fuser", "-k", f"{PORT}/tcp"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)
    for _ in range(20):
        if not is_port_open():
            return
        time.sleep(0.1)
    pytest.fail(f"Could not clear port {PORT} before starting the submitted server")


def start_submitted_server():
    global SERVER_PROC
    assert os.path.isfile(SERVER_PATH), f"Server script not found at {SERVER_PATH}."
    assert not is_port_open(), f"Port {PORT} was already occupied"
    SERVER_PROC = subprocess.Popen(
        ["python3", SERVER_PATH],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    for _ in range(30):
        if is_port_open():
            return
        if SERVER_PROC.poll() is not None:
            pytest.fail(f"Server at {SERVER_PATH} exited before binding to {HOST}:{PORT}")
        time.sleep(0.2)
    kill_listener()
    pytest.fail(f"Server at {SERVER_PATH} failed to start or bind to {HOST}:{PORT}")


@pytest.fixture(scope="session", autouse=True)
def ensure_server_running():
    kill_listener()

    # Remove any placeholder or stale output and require the repaired Makefile
    # to produce the requested artifact itself.
    try:
        os.unlink(SO_PATH)
    except FileNotFoundError:
        pass
    build = subprocess.run(
        ["make", "-B", "libmatrix_ops.so"],
        cwd="/app/legacy_calc",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert build.returncode == 0, f"Makefile failed to build libmatrix_ops.so:\n{build.stdout}"

    start_submitted_server()
    yield
    kill_listener()


def authenticated_request(value):
    headers = {
        "Authorization": f"Bearer {TOKEN}",
        "Content-Type": "application/json",
    }
    try:
        return requests.post(URL, headers=headers, json={"value": value}, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to server: {exc}")


def assert_ok_result(response, expected, tolerance=0.0001):
    assert response.status_code == 200, (
        f"Expected status 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert data.get("status") == "ok", f"Expected status 'ok', got {data.get('status')}"
    result = data.get("result")
    assert result is not None, "Response JSON missing 'result' field."
    assert isinstance(result, (int, float)), f"Result is not numeric: {result!r}"
    assert abs(result - expected) < tolerance, f"Expected result {expected}, got {result}"


def test_shared_library_compiled():
    assert os.path.isfile(SO_PATH), f"Shared library not found at {SO_PATH}. Did you compile the C code?"
    assert os.path.getsize(SO_PATH) > 0, "Shared library is empty"
    with open(SO_PATH, "rb") as artifact:
        assert artifact.read(4) == b"\x7fELF", "libmatrix_ops.so is not an ELF binary"

    try:
        library = ctypes.CDLL(SO_PATH)
        function = library.compute_calibrated
    except (OSError, AttributeError) as exc:
        pytest.fail(f"Shared library is not loadable or does not export compute_calibrated: {exc}")

    function.argtypes = [ctypes.c_double, ctypes.c_double]
    function.restype = ctypes.c_double
    values = [-17.25, 0.0, 2.5, random.SystemRandom().uniform(-1000.0, 1000.0)]
    for value in values:
        expected = value * COEFF + 100.0
        actual = function(value, COEFF)
        assert abs(actual - expected) < 1e-9 * max(1.0, abs(expected)), (
            f"compute_calibrated({value}, {COEFF}) returned {actual}, expected {expected}"
        )


def test_process_authenticated_success():
    response = authenticated_request(10.0)
    assert_ok_result(response, 131.4159)


def test_process_missing_auth():
    headers = {"Content-Type": "application/json"}
    payload = {"value": 10.0}
    try:
        response = requests.post(URL, headers=headers, json=payload, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to server: {exc}")
    assert response.status_code == 401, (
        f"Expected status 401 for missing auth, got {response.status_code}. Response: {response.text}"
    )


def test_process_invalid_auth():
    headers = {
        "Authorization": "Bearer INVALID-TOKEN",
        "Content-Type": "application/json",
    }
    payload = {"value": 10.0}
    try:
        response = requests.post(URL, headers=headers, json=payload, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to server: {exc}")
    assert response.status_code == 401, (
        f"Expected status 401 for invalid auth, got {response.status_code}. Response: {response.text}"
    )


def test_server_uses_library_and_base_multiplier():
    # Replace the library only after validating the submitted build. A fresh,
    # unpredictable probe implementation makes constant/formula-only servers
    # fail and also verifies that BASE_MULTIPLIER is passed as the second arg.
    kill_listener()
    rng = random.SystemRandom()
    a = rng.uniform(7.0, 19.0)
    b = rng.uniform(23.0, 47.0)
    c = rng.uniform(-500.0, 500.0)
    nonce = rng.randrange(1 << 62)
    directory = os.path.dirname(SO_PATH)
    source_path = os.path.join(directory, f".verifier_probe_{nonce}.c")
    probe_path = os.path.join(directory, f".verifier_probe_{nonce}.so")
    backup_path = os.path.join(directory, f".verifier_original_{nonce}.so")
    shutil.copy2(SO_PATH, backup_path)

    try:
        with open(source_path, "w", encoding="utf-8") as source:
            source.write(
                "double compute_calibrated(double input, double coeff) {\n"
                f"    return (input * {a!r}) + (coeff * {b!r}) + {c!r};\n"
                "}\n"
            )
        compile_result = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-O2", "-o", probe_path, source_path],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        assert compile_result.returncode == 0, f"Verifier probe compilation failed:\n{compile_result.stdout}"
        os.replace(probe_path, SO_PATH)
        start_submitted_server()

        for value in [rng.uniform(-200.0, -1.0), rng.uniform(1.0, 200.0), rng.uniform(300.0, 900.0)]:
            expected = value * a + COEFF * b + c
            response = authenticated_request(value)
            assert_ok_result(response, expected, 1e-8 * max(1.0, abs(expected)))
    finally:
        kill_listener()
        if os.path.exists(backup_path):
            os.replace(backup_path, SO_PATH)
        for path in (source_path, probe_path):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
