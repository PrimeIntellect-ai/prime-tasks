#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_memory_report_exists():
    file_path = "/home/user/memory_report.json"
    assert os.path.isfile(file_path), f"The output file {file_path} is missing."

def test_memory_report_content():
    file_path = "/home/user/memory_report.json"
    if not os.path.isfile(file_path):
        pytest.fail(f"Cannot verify content because {file_path} is missing.")

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} does not contain valid JSON.")

    assert isinstance(data, list), "The JSON root must be an array (list)."

    expected_data = [
        {"timestamp": "2023-10-01 10:00:00", "total_memory": 0, "rolling_avg": 0.0},
        {"timestamp": "2023-10-01 10:01:00", "total_memory": 512, "rolling_avg": 256.0},
        {"timestamp": "2023-10-01 10:02:00", "total_memory": 768, "rolling_avg": 426.67},
        {"timestamp": "2023-10-01 10:03:00", "total_memory": 768, "rolling_avg": 682.67},
        {"timestamp": "2023-10-01 10:04:00", "total_memory": 1280, "rolling_avg": 938.67},
        {"timestamp": "2023-10-01 10:05:00", "total_memory": 1280, "rolling_avg": 1109.33},
        {"timestamp": "2023-10-01 10:06:00", "total_memory": 1536, "rolling_avg": 1365.33},
        {"timestamp": "2023-10-01 10:07:00", "total_memory": 1536, "rolling_avg": 1450.67},
        {"timestamp": "2023-10-01 10:08:00", "total_memory": 1536, "rolling_avg": 1536.0},
        {"timestamp": "2023-10-01 10:09:00", "total_memory": 1536, "rolling_avg": 1536.0},
        {"timestamp": "2023-10-01 10:10:00", "total_memory": 1536, "rolling_avg": 1536.0}
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, but found {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not an object."

        # Check keys
        expected_keys = {"timestamp", "total_memory", "rolling_avg"}
        assert set(actual.keys()) == expected_keys, f"Item at index {i} has incorrect keys. Expected {expected_keys}, got {set(actual.keys())}."

        # Check types
        assert isinstance(actual["timestamp"], str), f"Item at index {i}: 'timestamp' must be a string."
        assert isinstance(actual["total_memory"], int), f"Item at index {i}: 'total_memory' must be an integer."
        assert isinstance(actual["rolling_avg"], float), f"Item at index {i}: 'rolling_avg' must be a float."

        # Check values
        assert actual["timestamp"] == expected["timestamp"], f"Item at index {i}: expected timestamp {expected['timestamp']}, got {actual['timestamp']}."
        assert actual["total_memory"] == expected["total_memory"], f"Item at index {i}: expected total_memory {expected['total_memory']}, got {actual['total_memory']}."
        assert actual["rolling_avg"] == expected["rolling_avg"], f"Item at index {i}: expected rolling_avg {expected['rolling_avg']}, got {actual['rolling_avg']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
