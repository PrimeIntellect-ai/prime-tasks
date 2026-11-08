#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_etl_c_exists():
    path = "/home/user/etl.c"
    assert os.path.isfile(path), f"Source file {path} does not exist."

def test_etl_binary_exists():
    path = "/home/user/etl"
    assert os.path.isfile(path), f"Executable file {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."

def test_processed_data_content():
    processed_path = "/home/user/processed_data.csv"
    expected_path = "/tests/expected_data.csv"

    assert os.path.isfile(processed_path), f"Output file {processed_path} does not exist."
    assert os.path.isfile(expected_path), f"Expected file {expected_path} does not exist."

    with open(processed_path, "r") as f:
        processed_content = f.read().strip()

    with open(expected_path, "r") as f:
        expected_content = f.read().strip()

    assert processed_content == expected_content, "The content of processed_data.csv does not match the expected output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
