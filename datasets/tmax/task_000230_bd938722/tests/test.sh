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
import json
import os
import secrets

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
TOKEN = "SECRET-ETL-774"
HEADERS = {"Authorization": f"Bearer {TOKEN}"}

PAYLOAD = """{"tx_id": "cfg_db_host", "timestamp": 100, "config_value": "db1.local"}
{"tx_id": "cfg_db_port", "timestamp": 105, "config_value": "5432"}
{"tx_id": "cfg_db_host", "timestamp": 90, "config_value": "old.db.local"}
{"tx_id": "cfg_db_port", "timestamp": 110, "config_value": "5433"}"""


def post(payload, headers=None):
    try:
        return requests.post(f"{BASE_URL}/ingest", headers=headers, data=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the server. Is it running on 127.0.0.1:8080?")


def get_state():
    try:
        response = requests.get(f"{BASE_URL}/state", timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Could not connect to the server. Is it running on 127.0.0.1:8080?")
    assert response.status_code == 200, f"Expected 200 OK for state, got {response.status_code}"
    value = response.json()
    assert isinstance(value, dict), f"Expected state to be a JSON object, got {type(value).__name__}"
    return value


def test_01_ingest_unauthorized():
    resp1 = post(PAYLOAD)
    assert resp1.status_code == 401, f"Expected 401 without auth, got {resp1.status_code}"

    resp2 = post(PAYLOAD, {"Authorization": "Bearer BAD-TOKEN"})
    assert resp2.status_code == 401, f"Expected 401 with bad auth, got {resp2.status_code}"


def test_02_ingest_and_state():
    resp_post = post(PAYLOAD, HEADERS)
    assert resp_post.status_code == 200, f"Expected 200 OK for ingest, got {resp_post.status_code}"

    state_data = get_state()
    expected_state = {
        "cfg_db_host": "db1.local",
        "cfg_db_port": "5433"
    }
    assert state_data.get("cfg_db_host") == "db1.local", f"Expected cfg_db_host to be 'db1.local', got {state_data.get('cfg_db_host')}"
    assert state_data.get("cfg_db_port") == "5433", f"Expected cfg_db_port to be '5433', got {state_data.get('cfg_db_port')}"


def test_03_dropped_log():
    log_path = "/home/user/dropped.log"
    assert os.path.exists(log_path), f"Dropped log file not found at {log_path}"

    with open(log_path, "r") as f:
        lines = f.read().strip().split("\n")

    found = False
    for line in lines:
        if not line.strip():
            continue
        try:
            record = json.loads(line)
            if record.get("tx_id") == "cfg_db_host" and record.get("timestamp") == 90 and record.get("config_value") == "old.db.local":
                found = True
                break
        except json.JSONDecodeError:
            pass

    assert found, f"Expected dropped record not found in {log_path}. File contents: {lines}"


def test_04_randomized_streaming_deduplication_and_exact_logging():
    suffix = secrets.token_hex(12)
    key_a = f"audit_A_{suffix}"
    key_b = f"audit_B_{suffix}"
    key_c = f"audit_C_{suffix}"
    rejected_key = f"audit_rejected_{suffix}"
    base = 100000 + secrets.randbelow(800000)

    rejected_raw = json.dumps({
        "tx_id": rejected_key,
        "timestamp": base + 500,
        "config_value": f"must_not_appear_{suffix}",
    }, separators=(",", ":"))
    assert post(rejected_raw).status_code == 401
    assert post(rejected_raw, {"Authorization": f"Bearer wrong-{suffix}"}).status_code == 401
    assert rejected_key not in get_state(), "An unauthorized record changed the state"

    initial_a = f"initial_A_{suffix}"
    initial_b = f"initial_B_{suffix}"
    first_payload = "\n".join([
        json.dumps({"tx_id": key_a, "timestamp": base, "config_value": initial_a}),
        json.dumps({"tx_id": key_b, "timestamp": base - 20, "config_value": initial_b}),
    ])
    response = post(first_payload, HEADERS)
    assert response.status_code == 200, f"Expected 200 for initial randomized ingest, got {response.status_code}"
    state = get_state()
    assert state.get(key_a) == initial_a
    assert state.get(key_b) == initial_b

    log_path = "/home/user/dropped.log"
    before = open(log_path, "rb").read() if os.path.exists(log_path) else b""

    older_a_value = f"older_A_{suffix}"
    equal_a_value = f"equal_A_{suffix}"
    newest_b_value = f"newest_B_{suffix}"
    c_low_value = f"C_low_{suffix}"
    c_high_value = f"C_high_{suffix}"
    c_mid_value = f"C_mid_{suffix}"

    # Deliberately vary JSON whitespace so the log must preserve each discarded raw line.
    older_a = f'{{"tx_id" : "{key_a}", "timestamp": {base - 7},    "config_value" : "{older_a_value}"}}'
    equal_a = f'{{ "tx_id": "{key_a}",  "timestamp" : {base}, "config_value": "{equal_a_value}" }}'
    newer_b = json.dumps({"tx_id": key_b, "timestamp": base + 30, "config_value": newest_b_value}, separators=(",", ":"))
    c_low = json.dumps({"tx_id": key_c, "timestamp": base + 1, "config_value": c_low_value})
    c_high = json.dumps({"tx_id": key_c, "timestamp": base + 40, "config_value": c_high_value})
    c_mid = f'{{"tx_id":"{key_c}", "timestamp":{base + 9}, "config_value" : "{c_mid_value}"}}'

    mixed_payload = "\n".join([older_a, equal_a, newer_b, c_low, c_high, c_mid])
    response = post(mixed_payload, HEADERS)
    assert response.status_code == 200, f"Expected 200 for duplicate ingest, got {response.status_code}"

    state = get_state()
    assert state.get(key_a) == initial_a, "An older or equal-timestamp record replaced the active value"
    assert state.get(key_b) == newest_b_value, "A newer timestamp did not replace the active value"
    assert state.get(key_c) == c_high_value, "The highest timestamp within one JSONL payload was not retained"
    assert rejected_key not in state

    assert os.path.exists(log_path), f"Dropped log file not found at {log_path}"
    after = open(log_path, "rb").read()
    assert after.startswith(before), "The dropped log was replaced instead of appended to"
    appended_lines = after[len(before):].decode("utf-8").splitlines()
    for expected_raw in (older_a, equal_a, c_mid):
        assert expected_raw in appended_lines, (
            f"Discarded record was not appended as its exact raw JSON line: {expected_raw!r}; "
            f"new log lines were {appended_lines!r}"
        )

    # Exercise cross-request timestamp comparison after the preceding state was established.
    late_old_b_value = f"late_old_B_{suffix}"
    late_old_b = f'{{"tx_id" : "{key_b}","timestamp" : {base + 5},"config_value":"{late_old_b_value}"}}'
    before_second_drop = after
    response = post(late_old_b, HEADERS)
    assert response.status_code == 200
    assert get_state().get(key_b) == newest_b_value, "Timestamp ordering was not retained across requests"
    final_log = open(log_path, "rb").read()
    assert final_log.startswith(before_second_drop)
    assert late_old_b in final_log[len(before_second_drop):].decode("utf-8").splitlines(), \
        "A cross-request discarded record was not logged exactly"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
