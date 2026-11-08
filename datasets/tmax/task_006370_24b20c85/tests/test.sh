#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math

def test_processed_data_exists_and_valid_json():
    file_path = '/home/user/processed_data.json'
    assert os.path.isfile(file_path), f"The file {file_path} was not created."

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {file_path} is not valid JSON."

    assert isinstance(data, list), "The JSON output must be an array of objects."

def test_processed_data_content():
    file_path = '/home/user/processed_data.json'
    with open(file_path, 'r') as f:
        data = json.load(f)

    expected_data = [
        {
            "time_bucket": "2023-10-01T01:00:00Z",
            "machine_id": "M1",
            "avg_temp": 41.0,
            "avg_humidity": 30.0,
            "rolling_3h_temp": 41.0,
            "status": "ACTIVE"
        },
        {
            "time_bucket": "2023-10-01T01:00:00Z",
            "machine_id": "M3",
            "avg_temp": 55.0,
            "avg_humidity": 45.0,
            "rolling_3h_temp": 55.0,
            "status": "MAINTENANCE_REQUIRED"
        },
        {
            "time_bucket": "2023-10-01T02:00:00Z",
            "machine_id": "M1",
            "avg_temp": 44.0,
            "avg_humidity": 32.0,
            "rolling_3h_temp": 42.5,
            "status": "ACTIVE"
        },
        {
            "time_bucket": "2023-10-01T03:00:00Z",
            "machine_id": "M1",
            "avg_temp": 46.0,
            "avg_humidity": 34.0,
            "rolling_3h_temp": 43.67,
            "status": "ACTIVE"
        },
        {
            "time_bucket": "2023-10-01T03:00:00Z",
            "machine_id": "M3",
            "avg_temp": 60.0,
            "avg_humidity": 50.0,
            "rolling_3h_temp": 57.5,
            "status": "MAINTENANCE_REQUIRED"
        },
        {
            "time_bucket": "2023-10-01T04:00:00Z",
            "machine_id": "M1",
            "avg_temp": 50.0,
            "avg_humidity": 36.0,
            "rolling_3h_temp": 46.67,
            "status": "ACTIVE"
        }
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, got {len(data)}."

    # Check sorting
    sorted_data = sorted(data, key=lambda x: (x.get("time_bucket", ""), x.get("machine_id", "")))
    assert data == sorted_data, "The JSON array is not sorted chronologically by time_bucket, then alphabetically by machine_id."

    required_keys = {"time_bucket", "machine_id", "avg_temp", "avg_humidity", "rolling_3h_temp", "status"}

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert set(actual.keys()) == required_keys, f"Record {i} does not have the exact required keys. Expected {required_keys}, got {set(actual.keys())}."

        assert actual["time_bucket"] == expected["time_bucket"], f"Record {i} time_bucket mismatch: expected {expected['time_bucket']}, got {actual['time_bucket']}."
        assert actual["machine_id"] == expected["machine_id"], f"Record {i} machine_id mismatch: expected {expected['machine_id']}, got {actual['machine_id']}."
        assert actual["status"] == expected["status"], f"Record {i} status mismatch: expected {expected['status']}, got {actual['status']}."

        # Check numeric values with standard floating-point tolerances (rounded to 2 decimal places)
        assert math.isclose(actual["avg_temp"], expected["avg_temp"], abs_tol=0.01), f"Record {i} avg_temp mismatch: expected {expected['avg_temp']}, got {actual['avg_temp']}."
        assert math.isclose(actual["avg_humidity"], expected["avg_humidity"], abs_tol=0.01), f"Record {i} avg_humidity mismatch: expected {expected['avg_humidity']}, got {actual['avg_humidity']}."
        assert math.isclose(actual["rolling_3h_temp"], expected["rolling_3h_temp"], abs_tol=0.01), f"Record {i} rolling_3h_temp mismatch: expected {expected['rolling_3h_temp']}, got {actual['rolling_3h_temp']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
