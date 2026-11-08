#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_aggregated_results_exists():
    file_path = "/home/user/aggregated_results.json"
    assert os.path.exists(file_path), f"The file {file_path} is missing."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

def test_aggregated_results_content():
    file_path = "/home/user/aggregated_results.json"
    assert os.path.exists(file_path), f"The file {file_path} is missing."

    with open(file_path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} does not contain valid JSON.")

    expected_data = {
        "2023-11-15T00:00:00Z": {
            "record_count": 3,
            "longest_word": "12345678910"
        },
        "2023-11-15T04:00:00Z": {
            "record_count": 3,
            "longest_word": "Pneumonoultramicroscopicsilicovolcanoconiosis"
        },
        "2023-11-16T12:00:00Z": {
            "record_count": 2,
            "longest_word": "exactly"
        }
    }

    assert isinstance(data, dict), "The top-level JSON structure must be an object (dictionary)."

    # Check keys
    assert set(data.keys()) == set(expected_data.keys()), f"The bucket keys do not match. Expected {list(expected_data.keys())}, got {list(data.keys())}."

    # Check values
    for key, expected_val in expected_data.items():
        actual_val = data[key]
        assert isinstance(actual_val, dict), f"The value for bucket {key} must be an object."
        assert "record_count" in actual_val, f"Bucket {key} is missing 'record_count'."
        assert "longest_word" in actual_val, f"Bucket {key} is missing 'longest_word'."

        assert actual_val["record_count"] == expected_val["record_count"], f"Incorrect record_count for bucket {key}. Expected {expected_val['record_count']}, got {actual_val['record_count']}."
        assert actual_val["longest_word"] == expected_val["longest_word"], f"Incorrect longest_word for bucket {key}. Expected '{expected_val['longest_word']}', got '{actual_val['longest_word']}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
