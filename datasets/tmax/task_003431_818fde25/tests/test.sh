#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_lineage_results_exist_and_correct():
    results_path = "/home/user/lineage_results.json"

    # 1. Check if the output file exists
    assert os.path.exists(results_path), f"Expected output file {results_path} does not exist."
    assert os.path.isfile(results_path), f"Expected {results_path} to be a file, but it is not."

    # 2. Load the JSON data
    try:
        with open(results_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse {results_path} as JSON. Error: {e}")
    except Exception as e:
        pytest.fail(f"Failed to read {results_path}. Error: {e}")

    # 3. Verify it's a list
    assert isinstance(data, list), f"Expected JSON root to be an array, got {type(data).__name__}."

    # 4. Verify the length (pagination top 5)
    assert len(data) == 5, f"Expected exactly 5 results in the JSON array, but found {len(data)}."

    # 5. Define the expected results
    expected_results = [
        {
            "paper_id": "AI-25",
            "title": "Modern AI 6",
            "year": 2023,
            "depth": 2
        },
        {
            "paper_id": "AI-24",
            "title": "Modern AI 5",
            "year": 2023,
            "depth": 4
        },
        {
            "paper_id": "AI-23",
            "title": "Modern AI 4",
            "year": 2022,
            "depth": 3
        },
        {
            "paper_id": "AI-22",
            "title": "Modern AI 3",
            "year": 2022,
            "depth": 4
        },
        {
            "paper_id": "AI-21",
            "title": "Modern AI 2",
            "year": 2021,
            "depth": 2
        }
    ]

    # 6. Compare the actual data to the expected data
    for i, (actual, expected) in enumerate(zip(data, expected_results)):
        assert isinstance(actual, dict), f"Expected item at index {i} to be an object, got {type(actual).__name__}."

        # Check keys
        expected_keys = {"paper_id", "title", "year", "depth"}
        actual_keys = set(actual.keys())
        assert actual_keys == expected_keys, f"Item at index {i} has incorrect keys. Expected {expected_keys}, got {actual_keys}."

        # Check values
        assert actual["paper_id"] == expected["paper_id"], f"Item at index {i}: Expected paper_id '{expected['paper_id']}', got '{actual['paper_id']}'."
        assert actual["title"] == expected["title"], f"Item at index {i}: Expected title '{expected['title']}', got '{actual['title']}'."
        assert actual["year"] == expected["year"], f"Item at index {i}: Expected year {expected['year']}, got {actual['year']}."
        assert actual["depth"] == expected["depth"], f"Item at index {i}: Expected depth {expected['depth']}, got {actual['depth']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
