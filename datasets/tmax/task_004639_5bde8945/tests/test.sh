#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

OUTPUT_PATH = "/home/user/config_impact.json"

def test_output_file_exists():
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file."

def test_output_is_valid_json():
    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"File {OUTPUT_PATH} is not valid JSON: {e}")

    assert isinstance(data, list), "Output JSON must be a list of dictionaries."
    for item in data:
        assert isinstance(item, dict), "Each item in the output JSON array must be a dictionary."

def test_output_content():
    with open(OUTPUT_PATH, 'r') as f:
        data = json.load(f)

    expected_data = [
        {
            "timestamp": "2023-10-01 09:58:15",
            "server_id": "server-A",
            "config_key": "cache_size",
            "config_value": "1024",
            "smoothed_cpu": 44.67
        },
        {
            "timestamp": "2023-10-01 10:01:45",
            "server_id": "server-B",
            "config_key": "timeout",
            "config_value": "30",
            "smoothed_cpu": 63.0
        },
        {
            "timestamp": "2023-10-01 10:04:30",
            "server_id": "server-A",
            "config_key": "max_workers",
            "config_value": "16",
            "smoothed_cpu": 66.67
        }
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, got {len(data)}."

    for i, expected_item in enumerate(expected_data):
        actual_item = data[i]
        assert "timestamp" in actual_item, f"Record {i} missing 'timestamp'"
        assert "server_id" in actual_item, f"Record {i} missing 'server_id'"
        assert "config_key" in actual_item, f"Record {i} missing 'config_key'"
        assert "config_value" in actual_item, f"Record {i} missing 'config_value'"
        assert "smoothed_cpu" in actual_item, f"Record {i} missing 'smoothed_cpu'"

        assert actual_item["timestamp"] == expected_item["timestamp"], f"Record {i} timestamp mismatch: expected {expected_item['timestamp']}, got {actual_item['timestamp']}"
        assert actual_item["server_id"] == expected_item["server_id"], f"Record {i} server_id mismatch: expected {expected_item['server_id']}, got {actual_item['server_id']}"
        assert actual_item["config_key"] == expected_item["config_key"], f"Record {i} config_key mismatch: expected {expected_item['config_key']}, got {actual_item['config_key']}"
        assert actual_item["config_value"] == expected_item["config_value"], f"Record {i} config_value mismatch: expected {expected_item['config_value']}, got {actual_item['config_value']}"

        # Check smoothed_cpu with a small tolerance for floating point differences if any, though it should be exactly rounded to 2 decimals
        assert abs(actual_item["smoothed_cpu"] - expected_item["smoothed_cpu"]) <= 0.01, f"Record {i} smoothed_cpu mismatch: expected {expected_item['smoothed_cpu']}, got {actual_item['smoothed_cpu']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
