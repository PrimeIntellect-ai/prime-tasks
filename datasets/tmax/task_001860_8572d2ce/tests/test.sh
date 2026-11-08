#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

OUTPUT_FILE = "/home/user/daily_max_temp.json"

def test_output_file_exists():
    """Check that the final JSON output file was created."""
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."

def test_output_file_content():
    """Check that the JSON output matches the expected structure and values."""
    with open(OUTPUT_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_FILE} does not contain valid JSON.")

    expected_data = {
        "DEVICE_01": {
            "2023-10-01": 26.0
        },
        "DEVICE_03": {
            "2023-10-01": 10.0,
            "2023-10-02": 12.0
        }
    }

    assert data == expected_data, f"JSON content in {OUTPUT_FILE} does not match expected output. Got: {data}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
