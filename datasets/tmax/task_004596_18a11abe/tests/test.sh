#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import pytest
from collections import Counter

CSV_PATH = "/home/user/config_dumps.csv"
JSON_PATH = "/home/user/long_configs.json"
REMEDIATION_PATH = "/home/user/remediation.conf"

def get_expected_data():
    if not os.path.exists(CSV_PATH):
        pytest.fail(f"Original CSV file {CSV_PATH} is missing, cannot compute truth.")

    with open(CSV_PATH, mode='r', encoding='utf-16le', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = list(reader)

    expected_json = []
    timeouts = []
    server_timeouts = {}

    for row in rows:
        server_id = row[0]
        for i, key in enumerate(header[1:], start=1):
            expected_json.append({
                "server": server_id,
                "key": key,
                "value": row[i]
            })
            if key == "timeout":
                timeouts.append(row[i])
                server_timeouts[server_id] = row[i]

    timeout_counts = Counter(timeouts)
    majority_timeout = None
    anomalous_timeout = None
    anomalous_server = None

    for val, count in timeout_counts.items():
        if count == 1:
            anomalous_timeout = val
        else:
            majority_timeout = val

    for srv, val in server_timeouts.items():
        if val == anomalous_timeout:
            anomalous_server = srv
            break

    expected_remediation = (
        f"Host: {anomalous_server}\n"
        f"Action: FIX_TIMEOUT\n"
        f"Expected: {majority_timeout}\n"
        f"Found: {anomalous_timeout}\n"
    )

    return expected_json, expected_remediation

def test_long_configs_json():
    """Test that long_configs.json is correctly generated."""
    assert os.path.exists(JSON_PATH), f"File {JSON_PATH} is missing."

    try:
        with open(JSON_PATH, 'r', encoding='utf-8') as f:
            actual_json = json.load(f)
    except Exception as e:
        pytest.fail(f"Failed to parse {JSON_PATH} as JSON: {e}")

    assert isinstance(actual_json, list), f"{JSON_PATH} should contain a JSON list."

    expected_json, _ = get_expected_data()

    # Sort both lists by server and key to compare robustly
    sorted_actual = sorted(actual_json, key=lambda x: (x.get("server", ""), x.get("key", "")))
    sorted_expected = sorted(expected_json, key=lambda x: (x["server"], x["key"]))

    assert len(sorted_actual) == len(sorted_expected), f"Expected {len(sorted_expected)} items in {JSON_PATH}, found {len(sorted_actual)}."

    for actual, expected in zip(sorted_actual, sorted_expected):
        assert actual == expected, f"Mismatch in JSON data. Expected {expected}, found {actual}."

def test_remediation_conf():
    """Test that remediation.conf is correctly generated."""
    assert os.path.exists(REMEDIATION_PATH), f"File {REMEDIATION_PATH} is missing."

    with open(REMEDIATION_PATH, 'r', encoding='utf-8') as f:
        actual_content = f.read().strip()

    _, expected_remediation = get_expected_data()
    expected_content = expected_remediation.strip()

    assert actual_content == expected_content, f"Content of {REMEDIATION_PATH} does not match expected format or values.\nExpected:\n{expected_content}\n\nFound:\n{actual_content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
