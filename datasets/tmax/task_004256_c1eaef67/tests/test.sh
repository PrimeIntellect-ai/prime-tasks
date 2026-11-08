#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_duplicates_json_exists_and_correct():
    file_path = "/home/user/duplicates.json"
    assert os.path.exists(file_path), f"The file {file_path} is missing."
    assert os.path.isfile(file_path), f"The path {file_path} is not a valid file."

    with open(file_path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} does not contain valid JSON.")

    expected_data = {
        "0": [0, 1],
        "2": [2, 3, 4],
        "5": [5, 6, 7],
        "8": [8, 9]
    }

    assert isinstance(data, dict), f"Expected JSON root to be an object (dict), got {type(data).__name__}."

    # Check that keys are strings and values are lists of integers
    for k, v in data.items():
        assert isinstance(k, str), f"Expected keys to be strings, but got {type(k).__name__} for key {k}."
        assert isinstance(v, list), f"Expected values to be lists, but got {type(v).__name__} for key {k}."
        assert all(isinstance(x, int) for x in v), f"Expected all elements in the list to be integers for key {k}."
        assert v == sorted(v), f"Expected the list of indices to be sorted for key {k}."

    assert data == expected_data, f"The duplicates data does not match the expected output. Got: {data}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
