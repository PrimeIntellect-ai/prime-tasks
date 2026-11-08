#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_cracked_creds_json_exists():
    """Test that the cracked_creds.json file exists."""
    json_path = "/home/user/cracked_creds.json"
    assert os.path.exists(json_path), f"The file {json_path} does not exist."
    assert os.path.isfile(json_path), f"The path {json_path} is not a file."

def test_cracked_creds_json_content():
    """Test that the cracked_creds.json file contains the correctly cracked credentials."""
    json_path = "/home/user/cracked_creds.json"

    if not os.path.exists(json_path):
        pytest.fail(f"Cannot check content because {json_path} does not exist.")

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"The file {json_path} does not contain valid JSON. Error: {e}")

    expected_data = {
        "albert": "1234",
        "bob": "9999",
        "sistema_admin": "0042"
    }

    assert isinstance(data, dict), f"The JSON in {json_path} must be a dictionary."
    assert data == expected_data, f"The contents of {json_path} do not match the expected cracked credentials. Expected {expected_data}, but got {data}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
