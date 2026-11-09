#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_top_suppliers_json_exists_and_correct():
    file_path = "/home/user/top_suppliers.json"

    # Assert file exists
    assert os.path.isfile(file_path), f"Output file {file_path} is missing. The script did not generate it."

    # Load JSON content
    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    # Expected data
    expected_data = [
        {"id": 2, "name": "Global Supplies"},
        {"id": 3, "name": "Fast Parts"},
        {"id": 5, "name": "Hidden Gems"}
    ]

    # Assert type is a list
    assert isinstance(data, list), f"Expected the JSON root to be a list, but got {type(data).__name__}."

    # Sort both lists by id just in case, though the prompt requires sorted ascending by id
    try:
        data_sorted = sorted(data, key=lambda x: x["id"])
    except KeyError:
        pytest.fail("One or more objects in the JSON list are missing the 'id' key.")

    expected_sorted = sorted(expected_data, key=lambda x: x["id"])

    # Check lengths
    assert len(data_sorted) == len(expected_sorted), f"Expected {len(expected_sorted)} suppliers, but found {len(data_sorted)}."

    # Check contents
    for i, (actual, expected) in enumerate(zip(data_sorted, expected_sorted)):
        assert "id" in actual, f"Item at index {i} is missing 'id'."
        assert "name" in actual, f"Item at index {i} is missing 'name'."

        assert isinstance(actual["id"], int), f"Item at index {i} has non-integer 'id'."
        assert isinstance(actual["name"], str), f"Item at index {i} has non-string 'name'."

        assert actual["id"] == expected["id"], f"Expected id {expected['id']} at index {i}, but got {actual['id']}."
        assert actual["name"] == expected["name"], f"Expected name '{expected['name']}' at index {i}, but got '{actual['name']}'."

    # Finally, assert exact equality to ensure ordering was correct in the raw data
    assert data == expected_data, "The JSON data does not exactly match the expected sorted output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
