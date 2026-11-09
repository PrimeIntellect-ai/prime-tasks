#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

OUTPUT_FILE = "/home/user/critical_path_summary.json"

def test_output_file_exists():
    """Verify that the output JSON file exists."""
    assert os.path.isfile(OUTPUT_FILE), f"Expected output file not found at {OUTPUT_FILE}"

def test_output_json_structure_and_values():
    """Verify the structure and values of the output JSON file."""
    with open(OUTPUT_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_FILE} does not contain valid JSON.")

    # Check required keys
    expected_keys = {"path", "task_durations", "total_duration"}
    assert set(data.keys()) == expected_keys, f"JSON keys do not match expected. Found: {list(data.keys())}"

    # Check 'path'
    expected_path = ["Extract_API", "Fast_Track", "Load_DW"]
    assert data["path"] == expected_path, f"Expected path {expected_path}, got {data['path']}"

    # Check 'task_durations'
    expected_durations = {
        "Extract_API": 10,
        "Fast_Track": 4,
        "Load_DW": 15
    }
    assert data["task_durations"] == expected_durations, f"Expected task_durations {expected_durations}, got {data['task_durations']}"

    # Check 'total_duration'
    expected_total = 29
    assert data["total_duration"] == expected_total, f"Expected total_duration {expected_total}, got {data['total_duration']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
