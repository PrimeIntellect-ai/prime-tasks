#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

REPORT_PATH = "/home/user/audit_report.json"

def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"The audit report was not found at {REPORT_PATH}."

def test_report_is_valid_json():
    try:
        with open(REPORT_PATH, 'r') as f:
            json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"The audit report at {REPORT_PATH} is not valid JSON. Error: {e}")
    except Exception as e:
        pytest.fail(f"Could not read the audit report: {e}")

def test_report_schema_and_content():
    with open(REPORT_PATH, 'r') as f:
        data = json.load(f)

    expected_keys = {
        "world_writable_files",
        "checksum_mismatches",
        "xss_vulnerable_files",
        "command_injection_files"
    }

    assert set(data.keys()) == expected_keys, f"The JSON report keys do not match the expected schema. Found: {list(data.keys())}"

    # Expected values based on the setup
    expected_data = {
        "world_writable_files": {"/home/user/webapp/index.html"},
        "checksum_mismatches": {"/home/user/webapp/index.html", "/home/user/webapp/utils.py"},
        "xss_vulnerable_files": {"/home/user/webapp/index.html"},
        "command_injection_files": {"/home/user/webapp/utils.py"}
    }

    for key, expected_set in expected_data.items():
        actual_list = data.get(key)
        assert isinstance(actual_list, list), f"The value for '{key}' must be a list."
        actual_set = set(actual_list)

        assert actual_set == expected_set, f"Mismatch in '{key}'. Expected {expected_set}, but got {actual_set}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
