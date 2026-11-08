#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

OUTPUT_PATH = '/home/user/author_summary.json'

def test_output_file_exists():
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist. Did you save the results?"
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file."

def test_output_json_format_and_content():
    try:
        with open(OUTPUT_PATH, 'r') as f:
            actual_data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse {OUTPUT_PATH} as JSON: {e}")
    except Exception as e:
        pytest.fail(f"Failed to read {OUTPUT_PATH}: {e}")

    assert isinstance(actual_data, list), f"Expected the root JSON element to be a list, got {type(actual_data).__name__}."

    expected_data = [
        {
            "community_size": 4,
            "top_author_id": 1,
            "top_author_name": "Dr. Alice"
        },
        {
            "community_size": 3,
            "top_author_id": 7,
            "top_author_name": "Dr. Grace"
        }
    ]

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} communities, found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a dictionary."

        # Check keys
        expected_keys = {"community_size", "top_author_id", "top_author_name"}
        actual_keys = set(actual.keys())
        assert actual_keys == expected_keys, f"Item at index {i} has incorrect keys. Expected {expected_keys}, got {actual_keys}."

        # Check values
        assert actual["community_size"] == expected["community_size"], f"Item {i}: expected community_size {expected['community_size']}, got {actual['community_size']}."
        assert actual["top_author_id"] == expected["top_author_id"], f"Item {i}: expected top_author_id {expected['top_author_id']}, got {actual['top_author_id']}."
        assert actual["top_author_name"] == expected["top_author_name"], f"Item {i}: expected top_author_name '{expected['top_author_name']}', got '{actual['top_author_name']}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
