#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_corrupted_csv():
    file_path = "/home/user/corrupted.csv"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."

    expected_lines = [
        "user_id,click_count,revenue",
        "102.0,8,250",
        "NaN,9,0",
        "106.0,10,300",
        "108.0,12,150"
    ]

    with open(file_path, "r") as f:
        content = f.read().strip().splitlines()

    # Check if header and content match
    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in {file_path}, but got {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual.strip() == expected, f"Line {i+1} in {file_path} is incorrect. Expected '{expected}', got '{actual.strip()}'."

def test_corrupted_revenue():
    file_path = "/home/user/corrupted_revenue.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == "700", f"Expected revenue sum to be '700', but got '{content}'."

def test_best_threshold():
    file_path = "/home/user/best_threshold.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == "7", f"Expected best threshold to be '7', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
