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

cleanup() {
    if [ -f /home/user/server.pid ]; then
        pid="$(cat /home/user/server.pid 2>/dev/null || true)"
        if [[ "$pid" =~ ^[0-9]+$ ]]; then
            kill "$pid" 2>/dev/null || true
        fi
    fi
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import py_compile
import secrets
import signal
import time

import pytest
import requests

URL = "http://127.0.0.1:8000/api/v1/sync"
MASTER_FILE = "/home/user/state/master.json"
LOG_FILE = "/home/user/state/sync.log"
PID_FILE = "/home/user/server.pid"
SERVER_FILE = "/home/user/sync_server.py"
INITIAL = [{"id": 100, "ts": 1690000000, "val": "INIT"}]


def hash_ids(ids):
    return hashlib.sha256("".join(map(str, ids)).encode()).hexdigest()


def post(client_id, transactions, checksum=None):
    if checksum is None:
        checksum = hash_ids([t["id"] for t in transactions])
    return requests.post(URL, json={
        "client_id": client_id,
        "checksum": checksum,
        "transactions": transactions,
    }, timeout=2)


def read_master():
    assert os.path.exists(MASTER_FILE), f"Master state file {MASTER_FILE} not found."
    with open(MASTER_FILE, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Master state file {MASTER_FILE} is not valid JSON.")


def read_logs():
    assert os.path.exists(LOG_FILE), f"Sync log file {LOG_FILE} not found."
    with open(LOG_FILE, "r") as f:
        return f.read().splitlines()


# Establish the required initial state after the agent has finished. This prevents
# a submission from satisfying the checks by prewriting the expected final files.
os.makedirs(os.path.dirname(MASTER_FILE), exist_ok=True)
with open(MASTER_FILE, "w") as f:
    json.dump(INITIAL, f)
try:
    os.remove(LOG_FILE)
except FileNotFoundError:
    pass


def test_server_pid_exists():
    assert os.path.isfile(SERVER_FILE), f"Server source {SERVER_FILE} not found."
    assert os.path.getsize(SERVER_FILE) > 0, f"Server source {SERVER_FILE} is empty."
    py_compile.compile(SERVER_FILE, doraise=True)

    assert os.path.exists(PID_FILE), f"PID file {PID_FILE} not found. Server may not be running in the background."
    with open(PID_FILE, 'r') as f:
        pid = f.read().strip()
    assert pid.isdigit(), f"PID file {PID_FILE} does not contain a valid integer PID."
    numeric_pid = int(pid)
    try:
        os.kill(numeric_pid, 0)
    except ProcessLookupError:
        pytest.fail(f"PID {numeric_pid} is not running.")
    cmdline_path = f"/proc/{numeric_pid}/cmdline"
    assert os.path.exists(cmdline_path), f"No live process information for PID {numeric_pid}."
    with open(cmdline_path, "rb") as f:
        cmdline = f.read().replace(b"\x00", b" ").decode(errors="replace")
    assert "sync_server.py" in cmdline, f"PID {numeric_pid} is not executing sync_server.py: {cmdline!r}"


def test_server_logic_and_state():
    # Test 1: Valid request
    tx1 = [{"id": 105, "ts": 1690000005, "val": "A"}, {"id": 102, "ts": 1690000001, "val": "B"}]
    try:
        resp1 = requests.post(URL, json={
            "client_id": "client_A",
            "checksum": hash_ids([105, 102]),
            "transactions": tx1
        }, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to server at {URL}: {e}")

    assert resp1.status_code == 200, f"Expected 200 for valid request, got {resp1.status_code}"

    # Test 2: Invalid checksum
    tx2 = [{"id": 108, "ts": 1690000010, "val": "C"}]
    resp2 = requests.post(URL, json={
        "client_id": "client_A",
        "checksum": "invalid_hash_value",
        "transactions": tx2
    }, timeout=2)
    assert resp2.status_code == 400, f"Expected 400 for invalid checksum, got {resp2.status_code}"

    # Test 3: Rate limiting
    tx3 = [{"id": 102, "ts": 1690000001, "val": "B_dup"}, {"id": 103, "ts": 1690000003, "val": "D"}]
    resp3 = requests.post(URL, json={
        "client_id": "client_A",
        "checksum": hash_ids([102, 103]),
        "transactions": tx3
    }, timeout=2)
    assert resp3.status_code == 429, f"Expected 429 for rate limit exceeded (3rd request), got {resp3.status_code}"

    # Test 4: Valid request on different client
    resp4 = requests.post(URL, json={
        "client_id": "client_B",
        "checksum": hash_ids([102, 103]),
        "transactions": tx3
    }, timeout=2)
    assert resp4.status_code == 200, f"Expected 200 for valid request on a new client, got {resp4.status_code}"

    # Verify State File
    master = read_master()
    expected_ids = [100, 102, 103, 105]
    actual_ids = [t.get('id') for t in master]
    assert actual_ids == expected_ids, f"Expected transaction IDs in order {expected_ids}, got {actual_ids}"

    # Verify Log File
    logs = read_logs()
    logs = [log for log in logs if log]
    assert len(logs) == 2, f"Expected exactly 2 log lines, got {len(logs)}"
    assert logs[0] == "SYNC client_A: Added 2 transactions: 102, 105", f"First log line mismatch: {logs[0]}"
    assert logs[1] == "SYNC client_B: Added 1 transactions: 103", f"Second log line mismatch: {logs[1]}"


def test_randomized_checksum_merge_sort_logging_and_rate_limit():
    client = "random_" + secrets.token_hex(12)
    other_client = "other_" + secrets.token_hex(12)
    empty_client = "empty_" + secrets.token_hex(12)
    ids = secrets.SystemRandom().sample(range(200000, 900000), 6)

    before = read_master()
    before_logs = read_logs()
    tx = [
        {"id": ids[0], "ts": 1690000030, "val": "random-A"},
        {"id": 102, "ts": 1, "val": "must-not-replace-existing"},
        {"id": ids[1], "ts": 1690000020, "val": "random-B"},
        {"id": ids[2], "ts": 1690000020, "val": "random-C"},
    ]
    response = post(client, tx)
    assert response.status_code == 200

    additions = [tx[0], tx[2], tx[3]]
    expected = sorted(before + additions, key=lambda item: (item["ts"], item["id"]))
    assert read_master() == expected, "Valid synchronization did not merge, preserve, and sort complete transaction objects correctly."
    expected_line = f"SYNC {client}: Added 3 transactions: " + ", ".join(map(str, sorted(ids[:3])))
    assert read_logs() == before_logs + [expected_line]

    # The checksum for the reverse order is valid for a different concatenation,
    # and therefore must be rejected. Unsuccessful requests must still consume quota.
    invalid_tx = [
        {"id": ids[3], "ts": 1690000008, "val": "invalid-A"},
        {"id": ids[4], "ts": 1690000007, "val": "invalid-B"},
    ]
    unchanged_state = read_master()
    unchanged_logs = read_logs()
    response = post(client, invalid_tx, hash_ids([ids[4], ids[3]]))
    assert response.status_code == 400
    assert read_master() == unchanged_state
    assert read_logs() == unchanged_logs

    rate_limited_tx = [{"id": ids[5], "ts": 1690000006, "val": "rate-limited"}]
    response = post(client, rate_limited_tx)
    assert response.status_code == 429, "An invalid-checksum request was not counted toward the per-client limit."
    assert read_master() == unchanged_state
    assert read_logs() == unchanged_logs

    # A different client may add the transaction rejected above, while an existing
    # ID in the same payload must not be replaced.
    response = post(other_client, [rate_limited_tx[0], {"id": ids[0], "ts": 0, "val": "replacement"}])
    assert response.status_code == 200
    expected = sorted(unchanged_state + rate_limited_tx, key=lambda item: (item["ts"], item["id"]))
    assert read_master() == expected
    expected_other_log = f"SYNC {other_client}: Added 1 transactions: {ids[5]}"
    assert read_logs() == unchanged_logs + [expected_other_log]

    # A successful request that adds nothing must still produce the specified line,
    # including its trailing space.
    state_before_empty = read_master()
    logs_before_empty = read_logs()
    response = post(empty_client, [{"id": ids[0], "ts": 0, "val": "ignored"}])
    assert response.status_code == 200
    assert read_master() == state_before_empty
    assert read_logs() == logs_before_empty + [f"SYNC {empty_client}: Added 0 transactions: "]


def test_ten_second_rolling_window_expires_old_requests():
    client = "rolling_" + secrets.token_hex(12)
    state_before = read_master()
    logs_before = read_logs()

    first = post(client, [])
    assert first.status_code == 200
    time.sleep(6.0)
    second = post(client, [])
    assert second.status_code == 200
    time.sleep(4.5)

    # The first request is now older than ten seconds, but the second is not.
    third = post(client, [])
    assert third.status_code == 200, "Requests older than the rolling ten-second window were not expired."
    fourth = post(client, [])
    assert fourth.status_code == 429, "More than two requests were accepted inside the current rolling window."

    assert read_master() == state_before
    line = f"SYNC {client}: Added 0 transactions: "
    assert read_logs() == logs_before + [line, line, line]


def test_teardown_server():
    if os.path.exists(PID_FILE):
        with open(PID_FILE, 'r') as f:
            pid_str = f.read().strip()
        if pid_str.isdigit():
            try:
                os.kill(int(pid_str), signal.SIGTERM)
            except ProcessLookupError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
