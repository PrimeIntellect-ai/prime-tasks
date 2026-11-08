#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json

def test_processed_logs_json():
    json_path = '/home/user/processed_logs.json'

    # Check if the output file exists
    assert os.path.isfile(json_path), f"Output file {json_path} is missing."

    # Parse the JSON file
    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} is not valid JSON."

    expected_data = [
      {"timestamp": "2023-10-01 10:00:00", "server_id": "PROD-A", "cpu_usage": 55.0},
      {"timestamp": "2023-10-01 10:01:00", "server_id": "PROD-A", "cpu_usage": 60.0},
      {"timestamp": "2023-10-01 10:02:00", "server_id": "PROD-A", "cpu_usage": 65.0},
      {"timestamp": "2023-10-01 10:03:00", "server_id": "PROD-A", "cpu_usage": 70.0},
      {"timestamp": "2023-10-01 10:04:00", "server_id": "PROD-A", "cpu_usage": 75.0},
      {"timestamp": "2023-10-01 11:00:00", "server_id": "PROD-B", "cpu_usage": 20.0},
      {"timestamp": "2023-10-01 11:01:00", "server_id": "PROD-B", "cpu_usage": 25.0},
      {"timestamp": "2023-10-01 11:02:00", "server_id": "PROD-B", "cpu_usage": 30.0},
      {"timestamp": "2023-10-01 11:03:00", "server_id": "PROD-B", "cpu_usage": 35.0},
      {"timestamp": "2023-10-01 11:04:00", "server_id": "PROD-B", "cpu_usage": 40.0}
    ]

    assert isinstance(data, list), "The JSON output must be a JSON array (list)."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, but found {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Record {i} is not a JSON object."

        assert actual.get('timestamp') == expected['timestamp'], (
            f"Record {i}: Expected timestamp '{expected['timestamp']}', got '{actual.get('timestamp')}'"
        )
        assert actual.get('server_id') == expected['server_id'], (
            f"Record {i}: Expected server_id '{expected['server_id']}', got '{actual.get('server_id')}'"
        )

        actual_cpu = actual.get('cpu_usage')
        assert actual_cpu is not None, f"Record {i}: Missing 'cpu_usage' key."
        assert isinstance(actual_cpu, (int, float)), f"Record {i}: 'cpu_usage' must be a number."
        assert round(actual_cpu, 2) == expected['cpu_usage'], (
            f"Record {i}: Expected cpu_usage {expected['cpu_usage']}, got {actual_cpu}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
