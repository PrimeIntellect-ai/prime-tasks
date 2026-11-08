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
import csv
import json
import os
import re
import time
from collections import Counter
from datetime import datetime

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"
CONFIG_FILE = "/home/user/current_config.json"
AUDIT_FILE = "/home/user/config_audit.log"
CSV_FILE = "/app/server_logs.csv"
AUTH = {"Authorization": "Bearer admin-token-2024"}
INITIAL_CONFIG = {
    "maintenance_mode": True,
    "max_workers": 42,
    "target_region": "eu-west-1",
    "log_level": "INFO",
    "retry_count": 3,
}
UPDATED_CONFIG = dict(INITIAL_CONFIG, max_workers=5, target_region="us-west-2")
LOG_RE = re.compile(
    r"^\[(?P<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?)\] "
    r"CONFIG_UPDATED: maintenance_mode=(?P<maintenance>true|false|True|False), "
    r"max_workers=(?P<workers>-?\d+), target_region=(?P<region>[^,\r\n]+)$"
)


def wait_for_server():
    for _ in range(30):
        try:
            response = requests.get(BASE_URL + "/config", timeout=1)
            if response.status_code in (200, 401, 403, 404):
                return
        except requests.exceptions.RequestException:
            pass
        time.sleep(0.5)
    pytest.fail(f"HTTP server did not start on {BASE_URL}")


def get_json(path, expected_status=200):
    response = requests.get(BASE_URL + path, timeout=10)
    assert response.status_code == expected_status, (
        f"Expected GET {path} to return {expected_status}, got "
        f"{response.status_code}. Response: {response.text}"
    )
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response body from GET {path} is not valid JSON: {response.text}")


def read_config_file():
    assert os.path.isfile(CONFIG_FILE), f"Configuration file not found at {CONFIG_FILE}"
    with open(CONFIG_FILE, encoding="utf-8") as handle:
        try:
            return json.load(handle)
        except ValueError as exc:
            pytest.fail(f"{CONFIG_FILE} is not valid JSON: {exc}")


def read_audit_lines():
    assert os.path.isfile(AUDIT_FILE), f"Audit log file not found at {AUDIT_FILE}"
    with open(AUDIT_FILE, encoding="utf-8") as handle:
        return handle.read().splitlines()


def parse_audit_line(line):
    match = LOG_RE.fullmatch(line)
    assert match is not None, f"Audit entry does not use the required exact format: {line!r}"
    timestamp = match.group("timestamp")
    try:
        datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    except ValueError:
        pytest.fail(f"Audit timestamp is not valid ISO 8601: {timestamp!r}")
    return {
        "maintenance_mode": match.group("maintenance").lower() == "true",
        "max_workers": int(match.group("workers")),
        "target_region": match.group("region"),
    }


def normalized_row(row, fieldnames):
    assert isinstance(row, dict), f"Sample row must be a JSON object, got {type(row).__name__}"
    assert set(row) == set(fieldnames), (
        f"Sample row fields must exactly match CSV columns {fieldnames}, got {sorted(row)}"
    )
    return tuple(str(row[name]) for name in fieldnames)


def test_complete_service_behavior():
    wait_for_server()

    # The transcription must have been merged with all untouched base fields and
    # persisted, not merely hardcoded into the HTTP response.
    initial_http = get_json("/config")
    assert initial_http == INITIAL_CONFIG, f"Unexpected initial /config payload: {initial_http}"
    assert initial_http.get("maintenance_mode") is True
    assert initial_http.get("max_workers") == 42
    assert initial_http.get("target_region") == "eu-west-1"
    assert initial_http.get("log_level") == "INFO"
    assert initial_http.get("retry_count") == 3
    assert read_config_file() == INITIAL_CONFIG

    initial_log = read_audit_lines()
    initial_entries = [parse_audit_line(line) for line in initial_log]
    assert any(entry == {
        "maintenance_mode": True,
        "max_workers": 42,
        "target_region": "eu-west-1",
    } for entry in initial_entries), "No correctly formatted initial transcription audit entry found"

    # Authentication must be enforced without changing persisted state or audit log.
    response = requests.post(BASE_URL + "/config", json={"max_workers": 7}, timeout=5)
    assert response.status_code in (401, 403), (
        f"Expected 401 or 403 when no auth provided, got {response.status_code}"
    )
    assert get_json("/config") == INITIAL_CONFIG
    assert read_config_file() == INITIAL_CONFIG
    assert read_audit_lines() == initial_log

    # Exercise the specified constraints with values whose outcomes are derived
    # directly from the stated ranges and types.
    invalid_payloads = [
        {"max_workers": 150},
        {"max_workers": 0},
        {"max_workers": 101},
        {"max_workers": 1.5},
        {"max_workers": True},
        {"target_region": "ap-south-1"},
        {"target_region": 123},
    ]
    for payload in invalid_payloads:
        response = requests.post(BASE_URL + "/config", json=payload, headers=AUTH, timeout=5)
        assert response.status_code == 400, (
            f"Expected 400 Bad Request for invalid payload {payload!r}, got "
            f"{response.status_code}. Response: {response.text}"
        )
        assert get_json("/config") == INITIAL_CONFIG
        assert read_config_file() == INITIAL_CONFIG
        assert read_audit_lines() == initial_log

    # A valid partial update must merge into the current configuration, persist,
    # be returned by subsequent GETs, and append exactly one correctly formatted entry.
    response = requests.post(
        BASE_URL + "/config",
        json={"max_workers": 5, "target_region": "us-west-2"},
        headers=AUTH,
        timeout=5,
    )
    assert response.status_code == 200, (
        f"Expected 200 OK for valid update, got {response.status_code}. Response: {response.text}"
    )
    assert get_json("/config") == UPDATED_CONFIG
    assert read_config_file() == UPDATED_CONFIG

    updated_log = read_audit_lines()
    assert updated_log[:len(initial_log)] == initial_log, "POST did not append to the audit log"
    assert len(updated_log) == len(initial_log) + 1, "Successful POST must append exactly one audit entry"
    assert len([line for line in updated_log if "CONFIG_UPDATED:" in line]) >= 2
    assert parse_audit_line(updated_log[-1]) == {
        "maintenance_mode": True,
        "max_workers": 5,
        "target_region": "us-west-2",
    }

    # Derive all strata and valid rows from the source CSV. Every returned row must
    # be an actual source row in the correct status stratum, without duplication.
    with open(CSV_FILE, newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames
        assert fieldnames == ["request_id", "timestamp", "status_code", "response_time"]
        source_by_status = {}
        for row in reader:
            source_by_status.setdefault(row["status_code"], []).append(row)

    sample = get_json("/sample")
    assert isinstance(sample, dict), "Expected sample response to be a JSON object"
    assert len(sample) > 0, "Expected sample response to contain keys for status codes"
    assert set(sample) == set(source_by_status), (
        f"Sample must contain every and only CSV status code; expected "
        f"{sorted(source_by_status)}, got {sorted(sample)}"
    )

    for status_code, records in sample.items():
        assert isinstance(records, list), f"Expected value for status code {status_code} to be a list"
        expected_count = min(UPDATED_CONFIG["max_workers"], len(source_by_status[status_code]))
        assert len(records) == expected_count, (
            f"Expected exactly {expected_count} records for status code {status_code}, got {len(records)}"
        )
        source_counter = Counter(
            tuple(row[name] for name in fieldnames) for row in source_by_status[status_code]
        )
        returned_counter = Counter(normalized_row(row, fieldnames) for row in records)
        for row_tuple, count in returned_counter.items():
            assert row_tuple[2] == status_code, (
                f"Row status_code {row_tuple[2]!r} does not match stratum key {status_code!r}"
            )
            assert source_counter[row_tuple] >= count, (
                f"Sample contains a row not present in the source stratum, or duplicates it: {row_tuple}"
            )

    # Confirm the service is still running and retains the POSTed state after sampling.
    assert get_json("/config") == UPDATED_CONFIG
    assert read_config_file() == UPDATED_CONFIG

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
