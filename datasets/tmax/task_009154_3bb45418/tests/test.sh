#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_deadlock_report_exists():
    """Verify that the deadlock report JSON file was created."""
    file_path = "/home/user/deadlock_report.json"
    assert os.path.isfile(file_path), f"Expected report file not found at {file_path}."

def test_deadlock_report_content():
    """Verify that the deadlock report contains the correct cycle counts."""
    file_path = "/home/user/deadlock_report.json"
    assert os.path.isfile(file_path), f"Report file {file_path} is missing."

    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {file_path} is not valid JSON.")
    except Exception as e:
        pytest.fail(f"Failed to read {file_path}: {e}")

    expected = {
        "T1": 1,
        "T2": 1,
        "T3": 1,
        "T4": 1,
        "T5": 2,
        "T6": 1,
        "T7": 1
    }

    assert isinstance(data, dict), "The JSON output must be a dictionary."

    # Check that keys and values match exactly
    assert data == expected, f"JSON content does not match expected output. Got: {data}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
