#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_merged_sensors_json_exists_and_correct():
    path = '/home/user/merged_sensors.json'
    assert os.path.isfile(path), f"The file {path} does not exist. The script did not generate the expected output file."

    try:
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {path} does not contain valid JSON.")
    except UnicodeError:
        pytest.fail(f"The file {path} is not encoded in UTF-8.")

    assert isinstance(data, list), f"The JSON data in {path} should be a list of objects (array of dictionaries)."

    expected_data = [
        {"timestamp": "2023-10-01T00:00:00Z", "temp_celsius": 22.0, "humidity_percent": 40.0},
        {"timestamp": "2023-10-01T00:10:00Z", "temp_celsius": 22.0, "humidity_percent": 40.0},
        {"timestamp": "2023-10-01T00:20:00Z", "temp_celsius": 22.5, "humidity_percent": 40.0},
        {"timestamp": "2023-10-01T00:30:00Z", "temp_celsius": 22.5, "humidity_percent": 40.0},
        {"timestamp": "2023-10-01T00:40:00Z", "temp_celsius": 22.5, "humidity_percent": 42.5},
        {"timestamp": "2023-10-01T00:50:00Z", "temp_celsius": 23.1, "humidity_percent": 42.5},
        {"timestamp": "2023-10-01T01:00:00Z", "temp_celsius": 23.1, "humidity_percent": 42.5},
        {"timestamp": "2023-10-01T01:10:00Z", "temp_celsius": 23.1, "humidity_percent": 42.5},
        {"timestamp": "2023-10-01T01:20:00Z", "temp_celsius": 23.1, "humidity_percent": 45.1},
        {"timestamp": "2023-10-01T01:30:00Z", "temp_celsius": 21.8, "humidity_percent": 45.1},
        {"timestamp": "2023-10-01T01:40:00Z", "temp_celsius": 21.8, "humidity_percent": 45.1},
        {"timestamp": "2023-10-01T01:50:00Z", "temp_celsius": 21.8, "humidity_percent": 44.0},
        {"timestamp": "2023-10-01T02:00:00Z", "temp_celsius": 22.2, "humidity_percent": 44.0}
    ]

    assert len(data) == len(expected_data), f"Expected exactly {len(expected_data)} records, but found {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Record at index {i} is not a dictionary."

        # Check keys
        expected_keys = {"timestamp", "temp_celsius", "humidity_percent"}
        assert set(actual.keys()) == expected_keys, f"Record at index {i} has incorrect keys. Expected {expected_keys}, got {set(actual.keys())}."

        # Check values
        assert actual["timestamp"] == expected["timestamp"], f"Record at index {i} has incorrect timestamp. Expected {expected['timestamp']}, got {actual['timestamp']}."

        # Use a small tolerance for float comparison in case of floating point inaccuracies
        assert abs(actual["temp_celsius"] - expected["temp_celsius"]) < 1e-5, f"Record at index {i} has incorrect temp_celsius. Expected {expected['temp_celsius']}, got {actual['temp_celsius']}."
        assert abs(actual["humidity_percent"] - expected["humidity_percent"]) < 1e-5, f"Record at index {i} has incorrect humidity_percent. Expected {expected['humidity_percent']}, got {actual['humidity_percent']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
