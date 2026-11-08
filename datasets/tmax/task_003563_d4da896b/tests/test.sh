#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import struct
import json
import glob
import pytest

CONFIGS_DIR = "/home/user/configs"
STATE_BIN = "/home/user/state.bin"
DIFF_JSON = "/home/user/config_diff.json"

def calculate_checksum(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()
    return sum(data) % 256

def test_config_diff_json():
    assert os.path.isfile(DIFF_JSON), f"{DIFF_JSON} was not created."

    with open(DIFF_JSON, 'r') as f:
        try:
            diff = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{DIFF_JSON} is not valid JSON.")

    expected_keys = {"added", "deleted", "modified", "unchanged"}
    assert set(diff.keys()) == expected_keys, f"{DIFF_JSON} keys do not match expected {expected_keys}."

    assert isinstance(diff["added"], list), "'added' must be a list"
    assert isinstance(diff["deleted"], list), "'deleted' must be a list"
    assert isinstance(diff["modified"], list), "'modified' must be a list"
    assert isinstance(diff["unchanged"], list), "'unchanged' must be a list"

    # Based on the fixed initial state and current files setup
    assert "network.conf" in diff["added"], "network.conf should be in 'added'"
    assert "legacy.conf" in diff["deleted"], "legacy.conf should be in 'deleted'"
    assert "app.conf" in diff["modified"], "app.conf should be in 'modified'"
    assert "db.conf" in diff["modified"], "db.conf should be in 'modified'"

    # Check alphabetical sorting
    for key in expected_keys:
        assert diff[key] == sorted(diff[key]), f"List for '{key}' is not sorted alphabetically."

def test_state_bin_updated():
    assert os.path.isfile(STATE_BIN), f"{STATE_BIN} is missing."

    # Calculate expected state from current files
    conf_files = glob.glob(os.path.join(CONFIGS_DIR, "*.conf"))
    expected_state = {}
    for filepath in conf_files:
        basename = os.path.basename(filepath)
        expected_state[basename.encode('utf-8')] = calculate_checksum(filepath)

    size = os.path.getsize(STATE_BIN)
    assert size % 64 == 0, f"{STATE_BIN} size ({size}) is not a multiple of 64 bytes."

    actual_state = {}
    with open(STATE_BIN, "rb") as f:
        while True:
            data = f.read(64)
            if not data:
                break
            name_bytes, checksum = struct.unpack("63sB", data)
            name = name_bytes.rstrip(b'\x00')
            actual_state[name] = checksum

    assert actual_state == expected_state, f"Updated state.bin records {actual_state} do not match expected {expected_state}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
