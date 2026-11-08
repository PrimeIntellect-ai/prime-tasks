#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_resolution_file_exists():
    assert os.path.isfile("/home/user/resolution.json"), "The file /home/user/resolution.json does not exist."

def test_resolution_file_content():
    try:
        with open("/home/user/resolution.json", "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("/home/user/resolution.json is not a valid JSON file.")

    assert isinstance(data, dict), "The JSON root must be a dictionary."

    expected_keys = {"faulty_file", "anomalous_variance", "crash_line"}
    missing_keys = expected_keys - data.keys()
    assert not missing_keys, f"Missing keys in resolution.json: {missing_keys}"

    # Verify faulty_file
    faulty_file = data["faulty_file"]
    assert isinstance(faulty_file, str), "The 'faulty_file' value must be a string."
    assert faulty_file == "data_37.csv", f"Incorrect 'faulty_file'. Expected 'data_37.csv', got '{faulty_file}'."

    # Verify anomalous_variance
    anomalous_variance = data["anomalous_variance"]
    assert isinstance(anomalous_variance, float), "The 'anomalous_variance' value must be a float."
    assert anomalous_variance == -42.42, f"Incorrect 'anomalous_variance'. Expected -42.42, got {anomalous_variance}."

    # Verify the source line containing the faulting memory access.
    crash_line = data["crash_line"]
    assert isinstance(crash_line, int), "The 'crash_line' value must be an integer."
    assert crash_line == 23, f"Incorrect 'crash_line'. Expected 23, got {crash_line}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
