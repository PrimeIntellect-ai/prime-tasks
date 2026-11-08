#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

RESOLUTION_FILE = "/home/user/resolution.json"

def test_resolution_file_exists():
    assert os.path.isfile(RESOLUTION_FILE), f"Resolution file {RESOLUTION_FILE} does not exist."

def test_resolution_content():
    assert os.path.isfile(RESOLUTION_FILE), f"Resolution file {RESOLUTION_FILE} does not exist."

    with open(RESOLUTION_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESOLUTION_FILE} is not a valid JSON.")

    assert "secret_key" in data, "Missing 'secret_key' in resolution.json"
    assert data["secret_key"] == "zulu_tango_99", f"Incorrect secret_key: {data['secret_key']}"

    assert "last_event_id" in data, "Missing 'last_event_id' in resolution.json"
    assert data["last_event_id"] == "evt_88421_crash", f"Incorrect last_event_id: {data['last_event_id']}"

    assert "repaired_timestamp" in data, "Missing 'repaired_timestamp' in resolution.json"
    assert data["repaired_timestamp"] == "2023-10-27T03:14:05+00:00", f"Incorrect repaired_timestamp: {data['repaired_timestamp']}"

    assert "recovered_db_row_count" in data, "Missing 'recovered_db_row_count' in resolution.json"
    assert data["recovered_db_row_count"] == 10, f"Incorrect recovered_db_row_count: {data['recovered_db_row_count']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
