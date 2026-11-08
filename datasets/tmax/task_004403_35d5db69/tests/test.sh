#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_recommendations_json_exists_and_correct():
    file_path = "/home/user/output/recommendations.json"

    # Check if the output file exists
    assert os.path.exists(file_path), f"Output file missing: {file_path}. Did you create it?"
    assert os.path.isfile(file_path), f"Path exists but is not a file: {file_path}"

    # Read and parse the JSON file
    try:
        with open(file_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {file_path} is not valid JSON.")
    except Exception as e:
        pytest.fail(f"Failed to read {file_path}: {e}")

    # Define the expected dictionary based on the instructed default
    # TfidfVectorizer behavior and strict similarity threshold.
    expected_data = {
        "E1": ["machine learning", "deep learning"],
        "E2": ["recipes", "kitchenware"]
    }

    # Assert that the actual data matches the expected data
    assert isinstance(data, dict), f"Expected the JSON root to be a dictionary, got {type(data).__name__}"
    assert data == expected_data, f"Content mismatch in {file_path}. Expected: {expected_data}, but got: {data}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
