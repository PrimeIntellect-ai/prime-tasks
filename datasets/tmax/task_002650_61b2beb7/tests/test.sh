#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_cleaned_reviews_file_exists():
    file_path = '/home/user/cleaned_reviews.jsonl'
    assert os.path.isfile(file_path), f"Output file {file_path} does not exist. Did you save the final processed data to the correct location?"

def test_cleaned_reviews_content():
    file_path = '/home/user/cleaned_reviews.jsonl'
    assert os.path.isfile(file_path), "Output file missing."

    expected_output = [
        {"username": "alice_x", "signup_date": "2023-01-01", "normalized_review": "great product really loved it"},
        {"username": "bob_99", "signup_date": "2023-02-15", "normalized_review": "terrible the packaging was completely destroyed"},
        {"username": "charlie_c", "signup_date": "2023-03-10", "normalized_review": "meh its okay i guess"},
        {"username": "eve_e", "signup_date": "2023-05-05", "normalized_review": "awesome 1010 would buy again"}
    ]

    actual_output = []
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, start=1):
                line = line.strip()
                if line:
                    try:
                        actual_output.append(json.loads(line))
                    except json.JSONDecodeError:
                        pytest.fail(f"Line {line_num} in {file_path} is not valid JSON. Ensure the file is in JSON Lines format.")
    except Exception as e:
        pytest.fail(f"Failed to read output file {file_path}: {e}")

    assert len(actual_output) == len(expected_output), f"Expected {len(expected_output)} records, but got {len(actual_output)}. Check your join conditions and data filtering."

    for i, (actual, expected) in enumerate(zip(actual_output, expected_output)):
        assert isinstance(actual, dict), f"Record at index {i} is not a JSON object."

        # Check keys
        expected_keys = set(expected.keys())
        actual_keys = set(actual.keys())
        assert actual_keys == expected_keys, f"Record at index {i} has incorrect keys. Expected {expected_keys}, got {actual_keys}."

        # Check values
        assert actual["username"] == expected["username"], f"Record at index {i} has incorrect username. Expected '{expected['username']}', got '{actual['username']}'."
        assert actual["signup_date"] == expected["signup_date"], f"Record at index {i} has incorrect signup_date. Expected '{expected['signup_date']}', got '{actual['signup_date']}'."
        assert actual["normalized_review"] == expected["normalized_review"], f"Record at index {i} has incorrect normalized_review. Expected '{expected['normalized_review']}', got '{actual['normalized_review']}'."

    # Check that they are sorted alphabetically by username
    usernames = [record["username"] for record in actual_output]
    assert usernames == sorted(usernames), "The output records are not sorted alphabetically by username."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
