#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_audit_page2_exists():
    file_path = "/home/user/audit_page2.json"
    assert os.path.exists(file_path), f"The output file {file_path} is missing. Please ensure your script saves the results to this location."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

def test_audit_page2_contents():
    file_path = "/home/user/audit_page2.json"
    assert os.path.exists(file_path), f"Cannot test contents because {file_path} is missing."

    try:
        with open(file_path, "r", encoding="utf-8") as f:
            actual_data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {file_path} does not contain valid JSON.")

    expected_data = [["T2", "T7"], ["T3", "T5"], ["T5", "T6"]]

    assert isinstance(actual_data, list), f"Expected the root JSON element to be a list, but got {type(actual_data).__name__}."
    assert actual_data == expected_data, f"The contents of {file_path} are incorrect. Expected {expected_data}, but got {actual_data}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
