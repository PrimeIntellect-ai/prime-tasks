#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

RESULTS_PATH = "/home/user/path_results.json"

def test_results_file_exists():
    """Check if the results JSON file was created."""
    assert os.path.exists(RESULTS_PATH), f"Results file {RESULTS_PATH} is missing."
    assert os.path.isfile(RESULTS_PATH), f"{RESULTS_PATH} is not a file."

def test_results_format_and_content():
    """Validate the contents of the results JSON file."""
    with open(RESULTS_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{RESULTS_PATH} does not contain valid JSON.")

    assert "path" in data, "Key 'path' is missing from the JSON output."
    assert "categories" in data, "Key 'categories' is missing from the JSON output."

    expected_path = ["P-START", "P-TRAP", "P-END"]
    assert data["path"] == expected_path, f"Expected path {expected_path}, but got {data['path']}."

    expected_categories = ["AI", "ML", "Magic", "Systems"]
    assert data["categories"] == expected_categories, f"Expected categories {expected_categories}, but got {data['categories']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
