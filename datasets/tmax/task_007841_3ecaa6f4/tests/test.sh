#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_summary_file_exists():
    assert os.path.isfile("/home/user/failed_docs_summary.json"), "The output file /home/user/failed_docs_summary.json is missing."

def test_summary_file_content():
    file_path = "/home/user/failed_docs_summary.json"

    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {file_path} is not valid JSON.")

    expected_data = {
        "auth.md": {
            "author": "Alice Johnson",
            "reason": "Invalid Markdown table syntax"
        },
        "api_v2.md": {
            "author": "John Smith",
            "reason": "Unresolved reference to 'UserEndpoint'"
        }
    }

    assert isinstance(data, dict), "The top-level JSON structure must be an object (dictionary)."

    # Check keys
    assert set(data.keys()) == set(expected_data.keys()), f"Expected keys {list(expected_data.keys())}, but got {list(data.keys())}."

    # Check values
    for key, expected_val in expected_data.items():
        actual_val = data[key]
        assert isinstance(actual_val, dict), f"The value for '{key}' must be an object."

        # Check author (case-insensitive key check just in case, but strict based on instructions is lowercase)
        assert "author" in actual_val, f"Missing 'author' key in the object for '{key}'."
        assert actual_val["author"] == expected_val["author"], f"Expected author '{expected_val['author']}' for '{key}', got '{actual_val['author']}'."

        # Check reason
        assert "reason" in actual_val, f"Missing 'reason' key in the object for '{key}'."
        assert actual_val["reason"] == expected_val["reason"], f"Expected reason '{expected_val['reason']}' for '{key}', got '{actual_val['reason']}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
