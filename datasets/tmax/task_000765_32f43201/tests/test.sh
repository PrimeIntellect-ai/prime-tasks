#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_top_rolling_csv_exists_and_correct():
    file_path = "/home/user/top_rolling.csv"

    # Check if the output file exists
    assert os.path.isfile(file_path), f"The output file {file_path} does not exist."

    # Expected contents based on the task description and logic
    expected_contents = [
        "2023-10-08,300",
        "2023-10-07,266",
        "2023-10-06,233"
    ]

    # Read actual contents
    with open(file_path, "r") as f:
        actual_contents = [line.strip() for line in f if line.strip()]

    assert actual_contents == expected_contents, (
        f"The contents of {file_path} are incorrect.\n"
        f"Expected:\n{chr(10).join(expected_contents)}\n"
        f"Got:\n{chr(10).join(actual_contents)}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
