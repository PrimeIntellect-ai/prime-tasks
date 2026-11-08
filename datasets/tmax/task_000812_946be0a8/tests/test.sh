#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_materialized_pipeline_json():
    file_path = "/home/user/materialized_pipeline.json"

    # Check if the file exists
    assert os.path.isfile(file_path), f"Missing expected output file: {file_path}"

    # Read and parse the JSON file
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse JSON in {file_path}: {e}")

    # Check for required keys
    assert "total_weight" in data, "Missing 'total_weight' key in the JSON output"
    assert "accepted_tx_ids" in data, "Missing 'accepted_tx_ids' key in the JSON output"

    # Verify the values
    expected_total_weight = 1480
    expected_accepted_tx_ids = ["TX01", "TX02", "TX03", "TX05", "TX07", "TX08", "TX09"]

    assert data["total_weight"] == expected_total_weight, \
        f"Expected total_weight to be {expected_total_weight}, got {data['total_weight']}"

    assert isinstance(data["accepted_tx_ids"], list), \
        "Expected 'accepted_tx_ids' to be a list"

    assert sorted(data["accepted_tx_ids"]) == expected_accepted_tx_ids, \
        f"Expected accepted_tx_ids to be {expected_accepted_tx_ids}, got {data['accepted_tx_ids']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
