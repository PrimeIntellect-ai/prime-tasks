#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

REPORT_FILE = "/home/user/incident/report.json"

def test_report_file_exists():
    assert os.path.isfile(REPORT_FILE), f"The report file {REPORT_FILE} does not exist."

def test_report_file_content():
    assert os.path.isfile(REPORT_FILE), f"The report file {REPORT_FILE} does not exist."

    with open(REPORT_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_FILE} does not contain valid JSON.")

    assert isinstance(data, dict), f"The JSON in {REPORT_FILE} must be a dictionary/object."

    expected_keys = {"user_id", "exception"}
    actual_keys = set(data.keys())

    assert actual_keys == expected_keys, f"The JSON keys must be exactly {expected_keys}, but found {actual_keys}."

    assert data["user_id"] == "U-4091A", f"Expected user_id to be 'U-4091A', but got '{data['user_id']}'."
    assert data["exception"] == "ZeroDivisionError", f"Expected exception to be 'ZeroDivisionError', but got '{data['exception']}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
