#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_cleaned_timeseries_exists():
    file_path = "/home/user/cleaned_timeseries.csv"
    assert os.path.exists(file_path), f"The file {file_path} does not exist. Did you create it?"
    assert os.path.isfile(file_path), f"The path {file_path} is not a regular file."

def test_cleaned_timeseries_content():
    file_path = "/home/user/cleaned_timeseries.csv"
    assert os.path.exists(file_path), f"Missing {file_path}"

    expected_content = (
        "Date,Avg_Temp\n"
        "2023-10-01,21.0\n"
        "2023-10-02,21.0\n"
        "2023-10-03,21.0\n"
        "2023-10-04,25.0\n"
        "2023-10-05,23.5\n"
        "2023-10-06,23.5\n"
        "2023-10-07,19.0\n"
    )

    with open(file_path, "r", encoding="utf-8") as f:
        actual_content = f.read()

    # Normalize line endings to avoid issues with \r\n vs \n
    actual_lines = [line.strip() for line in actual_content.strip().splitlines()]
    expected_lines = [line.strip() for line in expected_content.strip().splitlines()]

    assert actual_lines == expected_lines, (
        f"The content of {file_path} does not match the expected output. "
        f"Expected:\n{expected_content}\nActual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
