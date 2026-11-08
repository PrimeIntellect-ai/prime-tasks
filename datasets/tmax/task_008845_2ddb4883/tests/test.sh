#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_top_users_json_exists():
    file_path = "/home/user/top_users.json"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing. The pipeline did not generate the required file."

def test_top_users_json_content():
    file_path = "/home/user/top_users.json"
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    assert isinstance(data, list), f"Expected the JSON root to be a list, but got {type(data).__name__}."
    assert len(data) == 4, f"Expected exactly 4 entries in the JSON array (top 2 per region), but got {len(data)}."

    expected_data = [
        {
            "region": "EU",
            "rank": 1,
            "username": "alice",
            "degree": 3,
            "volume": 600.0
        },
        {
            "region": "EU",
            "rank": 2,
            "username": "bob",
            "degree": 3,
            "volume": 200.0
        },
        {
            "region": "US",
            "rank": 1,
            "username": "david",
            "degree": 3,
            "volume": 950.0
        },
        {
            "region": "US",
            "rank": 2,
            "username": "eve",
            "degree": 2,
            "volume": 420.0
        }
    ]

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Expected item at index {i} to be a dictionary."

        # Check keys
        expected_keys = {"region", "rank", "username", "degree", "volume"}
        assert set(actual.keys()) == expected_keys, f"Item at index {i} has incorrect keys. Expected {expected_keys}, got {set(actual.keys())}."

        # Check values
        assert actual["region"] == expected["region"], f"Item at index {i}: expected region '{expected['region']}', got '{actual['region']}'."
        assert actual["rank"] == expected["rank"], f"Item at index {i}: expected rank {expected['rank']}, got {actual['rank']}."
        assert actual["username"] == expected["username"], f"Item at index {i}: expected username '{expected['username']}', got '{actual['username']}'."
        assert actual["degree"] == expected["degree"], f"Item at index {i}: expected degree {expected['degree']}, got {actual['degree']}."
        assert float(actual["volume"]) == float(expected["volume"]), f"Item at index {i}: expected volume {expected['volume']}, got {actual['volume']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
