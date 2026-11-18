#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_pipeline_summary():
    file_path = "/home/user/output/pipeline_summary.json"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    assert "invalid_activity_rows" in data, "Key 'invalid_activity_rows' missing in pipeline_summary.json."
    assert data["invalid_activity_rows"] == 2, f"Expected 2 invalid activity rows, got {data['invalid_activity_rows']}."

def test_daily_aggregation():
    file_path = "/home/user/output/daily_aggregation.json"
    assert os.path.isfile(file_path), f"File {file_path} does not exist."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    expected_data = [
        {
            "date": "2023-10-01",
            "country": "CA",
            "tier": "premium",
            "total_duration": 5,
            "action_count": 1
        },
        {
            "date": "2023-10-01",
            "country": "US",
            "tier": "free",
            "total_duration": 15,
            "action_count": 2
        },
        {
            "date": "2023-10-02",
            "country": "UK",
            "tier": "free",
            "total_duration": 5,
            "action_count": 1
        }
    ]

    assert isinstance(data, list), "daily_aggregation.json should contain a JSON array."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items in the array, got {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual == expected, f"Item at index {i} does not match expected. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
