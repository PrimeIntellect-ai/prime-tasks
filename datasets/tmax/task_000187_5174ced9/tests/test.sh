#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def compute_expected_results(telemetry_file):
    expected_invalid = []
    expected_changepoints = []

    valid_amounts = []

    with open(telemetry_file, 'r') as f:
        for line in f:
            raw_line = line.strip('\n')
            is_valid = True

            try:
                data = json.loads(raw_line)
                if not isinstance(data, dict):
                    is_valid = False
                else:
                    keys = set(data.keys())
                    if keys != {"tx_id", "amount", "status"}:
                        is_valid = False
                    elif not isinstance(data["tx_id"], int) or isinstance(data["tx_id"], bool):
                        is_valid = False
                    elif not isinstance(data["amount"], (int, float)) or isinstance(data["amount"], bool):
                        is_valid = False
                    elif not isinstance(data["status"], str):
                        is_valid = False
                    elif data["amount"] < 0:
                        is_valid = False
            except json.JSONDecodeError:
                is_valid = False

            if not is_valid:
                expected_invalid.append(raw_line)
            else:
                amount = data["amount"]
                if len(valid_amounts) >= 50:
                    moving_avg = sum(valid_amounts[-50:]) / 50.0
                    if amount > 3.0 * moving_avg:
                        expected_changepoints.append(str(data["tx_id"]))
                valid_amounts.append(amount)

    return expected_invalid, expected_changepoints

def test_invalid_records_file():
    """Test that invalid_records.jsonl contains exactly the expected invalid lines."""
    telemetry_file = "/home/user/telemetry.jsonl"
    invalid_file = "/home/user/invalid_records.jsonl"

    assert os.path.exists(invalid_file), f"File {invalid_file} does not exist."

    expected_invalid, _ = compute_expected_results(telemetry_file)

    with open(invalid_file, 'r') as f:
        actual_invalid = [line.strip('\n') for line in f.readlines()]

    assert actual_invalid == expected_invalid, f"Contents of {invalid_file} do not match expected invalid records."

def test_changepoints_file():
    """Test that changepoints.txt contains exactly the expected tx_ids."""
    telemetry_file = "/home/user/telemetry.jsonl"
    changepoints_file = "/home/user/changepoints.txt"

    assert os.path.exists(changepoints_file), f"File {changepoints_file} does not exist."

    _, expected_changepoints = compute_expected_results(telemetry_file)

    with open(changepoints_file, 'r') as f:
        actual_changepoints = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_changepoints == expected_changepoints, f"Contents of {changepoints_file} do not match expected changepoints."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
