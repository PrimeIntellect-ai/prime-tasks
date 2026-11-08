#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

OUTPUT_PATH = '/home/user/management_chain.json'

def test_management_chain_output():
    """Test that the management_chain.json file exists and contains the correct reporting chain."""
    assert os.path.exists(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH}"
    assert os.path.isfile(OUTPUT_PATH), f"Path {OUTPUT_PATH} is not a file"

    try:
        with open(OUTPUT_PATH, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse JSON from {OUTPUT_PATH}: {e}")
    except Exception as e:
        pytest.fail(f"Error reading {OUTPUT_PATH}: {e}")

    expected_chain = [
        "Alice Smith",
        "Diana Prince",
        "Charlie Brown",
        "Bob Johnson",
        "Zoe Davis"
    ]

    assert isinstance(data, list), f"Expected JSON array, got {type(data).__name__}"
    assert data == expected_chain, f"Incorrect management chain. Expected {expected_chain}, got {data}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
