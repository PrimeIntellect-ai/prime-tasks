#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_top_deadlocks_json_exists():
    """Test that the top_deadlocks.json file exists."""
    file_path = "/home/user/top_deadlocks.json"
    assert os.path.exists(file_path), f"The file {file_path} does not exist. Did you save your output?"
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

def test_top_deadlocks_json_content():
    """Test that the top_deadlocks.json file contains the correct parsed JSON."""
    file_path = "/home/user/top_deadlocks.json"

    # We expect the file to exist based on the previous test, but we check again to be safe
    if not os.path.exists(file_path):
        pytest.fail(f"Cannot check content because {file_path} is missing.")

    try:
        with open(file_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {file_path} does not contain valid JSON.")

    expected_data = [
        ["TX01", "TX02", "TX03"],
        ["TX01", "TX06", "TX07"],
        ["TX02", "TX04", "TX08"]
    ]

    assert data == expected_data, (
        f"The content of {file_path} is incorrect.\n"
        f"Expected: {expected_data}\n"
        f"Got: {data}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
