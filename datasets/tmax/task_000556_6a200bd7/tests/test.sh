#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_flagged_products_json_exists():
    file_path = "/home/user/flagged_products.json"
    assert os.path.exists(file_path), f"The file {file_path} does not exist. Did you save the output?"
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

def test_flagged_products_json_content():
    file_path = "/home/user/flagged_products.json"

    with open(file_path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {file_path} does not contain valid JSON.")

    assert isinstance(data, list), "The JSON output must be a list of dictionaries."

    expected_ids = [2, 3, 4, 9, 10]
    actual_ids = []

    for item in data:
        assert isinstance(item, dict), "Each item in the JSON array must be a dictionary."
        assert set(item.keys()) == {"id", "failure_reason"}, "Each dictionary must have exactly 'id' and 'failure_reason' keys."
        assert isinstance(item["id"], int), "The 'id' must be an integer."
        assert item["failure_reason"] in ["low_similarity", "invalid_length", "both"], "Invalid 'failure_reason' value."
        actual_ids.append(item["id"])

    assert actual_ids == sorted(actual_ids), "The JSON array must be sorted in ascending order by 'id'."
    assert actual_ids == expected_ids, f"Expected flagged IDs {expected_ids}, but got {actual_ids}."

    # Check specific failure reasons
    reasons_by_id = {item["id"]: item["failure_reason"] for item in data}

    assert reasons_by_id[2] == "invalid_length", "ID 2 should fail only due to invalid length."
    assert reasons_by_id[3] == "low_similarity", "ID 3 should fail only due to low similarity."
    assert reasons_by_id[4] in ["invalid_length", "both"], "ID 4 should fail due to invalid length, and possibly low similarity."
    assert reasons_by_id[9] == "both", "ID 9 should fail due to both constraints."
    assert reasons_by_id[10] == "low_similarity", "ID 10 should fail only due to low similarity."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
