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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import datetime
import json
import os
import random
import re
import shutil
import signal
import socket
import sqlite3
import subprocess
import time

import pytest
import requests

APP_DIR = "/home/user/app"
BACKEND_DIR = os.path.join(APP_DIR, "backend")
DATA_DIR = os.path.join(APP_DIR, "data")
DB_PATH = os.path.join(DATA_DIR, "analytics.db")
LIB_PATH = os.path.join(BACKEND_DIR, "libanalyzer.so")
API_URL = "http://127.0.0.1:8080/ingest"
RNG = random.SystemRandom()


def expected_score(user_id, attempts):
    return attempts * 1.5 + user_id % 10


def post_api(payload):
    try:
        return requests.post(API_URL, json=payload, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to API at {API_URL}: {exc}")


def call_backend(payload, timeout=5):
    try:
        with socket.create_connection(("127.0.0.1", 9090), timeout=timeout) as client:
            client.sendall(json.dumps(payload).encode("utf-8"))
            client.shutdown(socket.SHUT_WR)
            chunks = []
            while True:
                chunk = client.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
    except OSError as exc:
        pytest.fail(f"Backend is not accepting raw TCP connections on 127.0.0.1:9090: {exc}")
    assert chunks, "Backend returned no TCP response"
    try:
        return json.loads(b"".join(chunks).decode("utf-8"))
    except Exception as exc:
        pytest.fail(f"Backend returned invalid JSON: {exc}")


def test_libanalyzer_built_and_loadable():
    assert os.path.isfile(LIB_PATH), f"Missing shared library: {LIB_PATH}. Did you compile analyzer.c?"

    class AnalyticsPayload(ctypes.Structure):
        _fields_ = [("user_id", ctypes.c_int), ("attempts", ctypes.c_int)]

    try:
        library = ctypes.CDLL(LIB_PATH)
        compute = library.compute_risk_score
        compute.argtypes = [ctypes.POINTER(AnalyticsPayload)]
        compute.restype = ctypes.c_double
    except Exception as exc:
        pytest.fail(f"libanalyzer.so is not a loadable shared library with compute_risk_score: {exc}")

    for _ in range(12):
        user_id = RNG.randint(1, 100000)
        attempts = RNG.randint(-20, 20)
        payload = AnalyticsPayload(user_id=user_id, attempts=attempts)
        assert compute(ctypes.byref(payload)) == pytest.approx(expected_score(user_id, attempts))


def test_database_schema_and_data_migrated():
    assert os.path.isfile(DB_PATH), f"Missing database file: {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("PRAGMA table_info(events);")
        columns = cursor.fetchall()

        timestamp_col = next((col for col in columns if col[1] == "timestamp"), None)
        assert timestamp_col is not None, "Column 'timestamp' does not exist in 'events' table"
        assert timestamp_col[2].upper() == "TEXT", f"Column 'timestamp' should be of type TEXT, found {timestamp_col[2]}"

        iso_time_col = next((col for col in columns if col[1] == "iso_time"), None)
        assert iso_time_col is None, "Column 'iso_time' should have been renamed to 'timestamp'"

        cursor.execute("SELECT timestamp FROM events LIMIT 10;")
        rows = cursor.fetchall()
        assert len(rows) > 0, "No data found in events table"

        iso8601_regex = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
        for row in rows:
            ts = row[0]
            assert isinstance(ts, str), f"Timestamp '{ts}' is not a string"
            assert iso8601_regex.match(ts), f"Timestamp '{ts}' is not in the expected ISO 8601 format (e.g., 2023-10-05T14:48:00Z)"

        expected_rows = [
            (1, "login", "2023-10-05T14:48:00Z"),
            (2, "purchase", "2023-10-05T15:48:00Z"),
            (3, "logout", "2023-10-05T16:48:00Z"),
        ]
        cursor.execute("SELECT id, event_type, timestamp FROM events ORDER BY id")
        assert cursor.fetchall() == expected_rows, "Seeded UNIX timestamps were not converted to their exact UTC ISO 8601 values"
    finally:
        conn.close()


def test_backend_tcp_service_randomized():
    for _ in range(10):
        user_id = RNG.randint(1, 1000000)
        attempts = RNG.randint(-25, 25)
        payload = {
            "user_id": user_id,
            "event_type": "direct-check",
            "metadata": {"attempts": attempts, "nonce": RNG.randint(1, 10**9)},
        }
        data = call_backend(payload)
        assert data.get("risk_score") == pytest.approx(expected_score(user_id, attempts))


def test_api_valid_request():
    payload = {
        "user_id": 42,
        "event_type": "login",
        "metadata": {"ip": "192.168.1.1", "attempts": 3},
    }
    response = post_api(payload)
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert data.get("status") == "success", f"Expected status 'success', got {data.get('status')}"
    expected = 3 * 1.5 + 42 % 10
    assert data.get("risk_score") == expected, f"Expected risk_score {expected}, got {data.get('risk_score')}"


def test_api_randomized_valid_requests():
    for _ in range(12):
        user_id = RNG.randint(1, 1000000)
        attempts = RNG.randint(-20, 5)
        payload = {
            "user_id": user_id,
            "event_type": f"event-{RNG.randint(1, 10**9)}",
            "metadata": {"attempts": attempts, "extra": RNG.randint(1, 10**9)},
        }
        response = post_api(payload)
        assert response.status_code == 200, response.text
        data = response.json()
        assert data.get("status") == "success"
        assert data.get("risk_score") == pytest.approx(expected_score(user_id, attempts))


def assert_validation_failure(payload):
    response = post_api(payload)
    assert response.status_code == 400, f"Expected HTTP 400 for validation failure, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert data.get("error") == "Validation failed", f"Expected error 'Validation failed', got {data.get('error')}"


def test_api_invalid_request_validation():
    payload = {
        "user_id": 42,
        "event_type": "login",
        "metadata": {"ip": "192.168.1.1", "attempts": 6},
    }
    assert_validation_failure(payload)


def test_api_missing_fields_validation():
    payload = {"user_id": 42, "event_type": "login"}
    assert_validation_failure(payload)


def test_api_randomized_validation_cases():
    for _ in range(6):
        assert_validation_failure({
            "user_id": RNG.randint(1, 100000),
            "event_type": "login",
            "metadata": {"attempts": RNG.randint(6, 1000)},
        })

    assert_validation_failure({"user_id": 0, "event_type": "login", "metadata": {"attempts": 1}})
    assert_validation_failure({"user_id": 7, "event_type": "", "metadata": {"attempts": 1}})
    assert_validation_failure({"event_type": "login", "metadata": {"attempts": 1}})
    assert_validation_failure({"user_id": 7, "metadata": {"attempts": 1}})
    assert_validation_failure({"user_id": 7, "event_type": "login", "metadata": None})


def backend_pids():
    found = []
    current = os.getpid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == current:
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as handle:
                command = handle.read().replace(b"\x00", b" ")
            if b"backend_tcp.py" in command:
                found.append(int(entry))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def stop_existing_backend():
    pids = backend_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and backend_pids():
        time.sleep(0.05)
    for pid in backend_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def wait_for_backend(process):
    deadline = time.time() + 5
    while time.time() < deadline:
        if process.poll() is not None:
            pytest.fail(f"backend_tcp.py exited during startup with status {process.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", 9090), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    pytest.fail("backend_tcp.py did not begin listening on 127.0.0.1:9090")


def start_backend():
    process = subprocess.Popen(
        ["python3", os.path.join(BACKEND_DIR, "backend_tcp.py")],
        cwd=BACKEND_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    wait_for_backend(process)
    return process


def test_z_backend_uses_shared_library_and_api_forwards_to_it():
    # Replace the library only after checking the submitted library's real behavior.
    # Runtime-random coefficients make it impossible for a fixed Python response or
    # reimplementation of the original formula to satisfy this test.
    multiplier = RNG.randint(7, 31)
    modulus = RNG.randint(37, 97)
    offset = RNG.randint(1000, 9000)
    source_path = "/tmp/verifier_probe_analyzer.c"
    probe_path = "/tmp/verifier_probe_libanalyzer.so"
    backup_path = os.path.join(BACKEND_DIR, ".libanalyzer.so.verifier-backup")
    probe_source = f"""
typedef struct {{ int user_id; int attempts; }} AnalyticsPayload;
double compute_risk_score(AnalyticsPayload* payload) {{
    return (payload->attempts * {multiplier}.0) + (payload->user_id % {modulus}) + {offset}.0;
}}
"""
    with open(source_path, "w") as handle:
        handle.write(probe_source)
    subprocess.run(["gcc", "-shared", "-fPIC", "-o", probe_path, source_path], check=True)

    probe_process = None
    shutil.copy2(LIB_PATH, backup_path)
    try:
        stop_existing_backend()
        os.replace(probe_path, LIB_PATH)
        probe_process = start_backend()

        for _ in range(5):
            user_id = RNG.randint(1, 1000000)
            attempts = RNG.randint(-10, 5)
            payload = {
                "user_id": user_id,
                "event_type": "ffi-probe",
                "metadata": {"attempts": attempts},
            }
            expected = attempts * multiplier + user_id % modulus + offset

            direct = call_backend(payload)
            assert direct.get("risk_score") == pytest.approx(expected), "backend_tcp.py did not use compute_risk_score from libanalyzer.so"

            response = post_api(payload)
            assert response.status_code == 200, response.text
            api_data = response.json()
            assert api_data.get("status") == "success"
            assert api_data.get("risk_score") == pytest.approx(expected), "Ingestion API did not forward the payload to the TCP backend"
    finally:
        if probe_process is not None and probe_process.poll() is None:
            probe_process.terminate()
            try:
                probe_process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                probe_process.kill()
                probe_process.wait(timeout=2)
        stop_existing_backend()
        if os.path.exists(backup_path):
            os.replace(backup_path, LIB_PATH)
        # Restore the required final running state even after the instrumentation.
        start_backend()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
