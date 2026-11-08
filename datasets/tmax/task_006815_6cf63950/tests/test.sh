#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_mutated_duplicates_file_exists():
    path = "/home/user/etl_workspace/mutated_duplicates.csv"
    assert os.path.isfile(path), f"The file {path} does not exist. Did you create it in the correct location?"

def test_mutated_duplicates_content():
    path = "/home/user/etl_workspace/mutated_duplicates.csv"
    assert os.path.isfile(path), "Output file is missing."

    expected_pairs = {
        "9876543210AB,9876543210AC",
        "ZXCVBNM09876,ZXCVBNM09877"
    }

    actual_pairs = set()
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if line:
                actual_pairs.add(line)

    assert actual_pairs == expected_pairs, (
        f"The content of {path} is incorrect.\n"
        f"Expected pairs: {expected_pairs}\n"
        f"Found pairs: {actual_pairs}"
    )

def test_extracted_files_exist():
    run1_path = "/home/user/etl_workspace/run1.csv"
    run2_path = "/home/user/etl_workspace/run2_retry.csv"

    assert os.path.isfile(run1_path), f"Extracted file {run1_path} is missing. Did you extract the archive correctly?"
    assert os.path.isfile(run2_path), f"Extracted file {run2_path} is missing. Did you extract the archive correctly?"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
