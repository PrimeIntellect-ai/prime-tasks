#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_output_file_exists():
    output_path = '/home/user/output/grouped_configs.json'
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."

def test_output_json_content():
    output_path = '/home/user/output/grouped_configs.json'

    with open(output_path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {output_path} does not contain valid JSON.")

    expected_data = {
        "c01b315252873cf181829e24f79417852c00e62df0ec2298cdeba3aa7f3b890a": [
            "srv-alpha",
            "srv-beta",
            "srv-delta"
        ],
        "6b1102e3b9e4a3c25af4c6eabcc1fcf98bb6020583e78f9f1fc7f7ba506d3fc2": [
            "srv-epsilon",
            "srv-gamma"
        ]
    }

    assert isinstance(data, dict), "The top-level JSON structure should be a dictionary (object)."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} keys in the JSON output, found {len(data)}."

    for key, expected_list in expected_data.items():
        assert key in data, f"Expected SHA-256 hash {key} is missing from the JSON keys."
        actual_list = data[key]
        assert isinstance(actual_list, list), f"The value for key {key} should be a list."
        assert actual_list == expected_list, f"The list of server_ids for hash {key} does not match the expected sorted list. Expected {expected_list}, got {actual_list}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
