#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

RESOLUTION_FILE = "/home/user/resolution.json"
EXPECTED_COMMIT_FILE = "/tests/.expected_bad_commit"

def test_resolution_file_exists():
    assert os.path.isfile(RESOLUTION_FILE), f"The file {RESOLUTION_FILE} does not exist. Did you create it?"

def test_resolution_file_valid_json():
    with open(RESOLUTION_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {RESOLUTION_FILE} does not contain valid JSON.")

    assert isinstance(data, dict), f"The JSON in {RESOLUTION_FILE} should be an object (dict)."
    assert "bad_commit" in data, f"The key 'bad_commit' is missing from {RESOLUTION_FILE}."
    assert "drift_amount" in data, f"The key 'drift_amount' is missing from {RESOLUTION_FILE}."

def test_bad_commit_matches_expected():
    assert os.path.isfile(EXPECTED_COMMIT_FILE), f"The expected commit file {EXPECTED_COMMIT_FILE} is missing."

    with open(EXPECTED_COMMIT_FILE, 'r') as f:
        expected_commit = f.read().strip()

    with open(RESOLUTION_FILE, 'r') as f:
        data = json.load(f)

    actual_commit = data.get("bad_commit", "")
    assert actual_commit == expected_commit, f"Expected bad_commit '{expected_commit}', but got '{actual_commit}'."

def test_drift_amount_matches_expected():
    with open(RESOLUTION_FILE, 'r') as f:
        data = json.load(f)

    drift_amount = data.get("drift_amount")
    assert drift_amount is not None, "drift_amount is null or missing."

    try:
        drift_val = float(drift_amount)
    except ValueError:
        pytest.fail(f"drift_amount '{drift_amount}' cannot be converted to a float.")

    rounded_drift = round(drift_val, 3)
    assert rounded_drift == 9.621, f"Expected drift_amount to be 9.621, but got {drift_val} (rounded to {rounded_drift})."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
