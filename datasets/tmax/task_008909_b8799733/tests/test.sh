#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_etl_pipeline_cpp_exists():
    assert os.path.isfile('/home/user/etl_pipeline.cpp'), "The C++ source file /home/user/etl_pipeline.cpp is missing."

def test_closest_csv_content():
    expected_content = [
        "test_id,closest_train_id",
        "101,1",
        "102,4",
        "103,5",
        "104,2"
    ]

    file_path = "/home/user/closest.csv"
    assert os.path.isfile(file_path), f"The output file {file_path} is missing."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_content, f"Content of {file_path} does not match expected output. Got: {lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
