#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json

def test_stratified_samples_json():
    file_path = '/home/user/stratified_samples.json'
    assert os.path.exists(file_path), f"The file {file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{file_path} does not contain valid JSON."

    assert isinstance(data, list), f"The JSON in {file_path} must be a list (array)."

    expected_data = [
        {
            "timestamp": "2023-10-12 10:05:01",
            "severity": "ERROR",
            "user_id": "1001",
            "error_code": "E-100"
        },
        {
            "timestamp": "2023-10-12 10:07:05",
            "severity": "ERROR",
            "user_id": "1003",
            "error_code": "E-100"
        },
        {
            "timestamp": "2023-10-12 10:20:00",
            "severity": "ERROR",
            "user_id": "1007",
            "error_code": "E-999"
        },
        {
            "timestamp": "2023-10-12 10:06:22",
            "severity": "WARNING",
            "user_id": "1002",
            "error_code": "W-042"
        },
        {
            "timestamp": "2023-10-12 10:15:30",
            "severity": "WARNING",
            "user_id": "1005",
            "error_code": "W-042"
        }
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items in {file_path}, but found {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        assert actual == expected, f"Item at index {i} does not match the expected output. Expected: {expected}, Actual: {actual}"

def test_etl_metrics_json():
    file_path = '/home/user/etl_metrics.json'
    assert os.path.exists(file_path), f"The file {file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{file_path} does not contain valid JSON."

    assert isinstance(data, dict), f"The JSON in {file_path} must be an object (dict)."

    expected_data = {
        "total_lines_read": 9,
        "total_errors_parsed": 7,
        "unique_error_codes": 3
    }

    assert data == expected_data, f"The metrics in {file_path} do not match the expected output. Expected: {expected_data}, Actual: {data}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
