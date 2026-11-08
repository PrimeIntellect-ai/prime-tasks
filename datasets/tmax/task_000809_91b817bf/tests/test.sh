#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_clean_timeseries_exists():
    assert os.path.isfile("/home/user/workspace/clean_timeseries.csv"), "The file /home/user/workspace/clean_timeseries.csv was not found."

def test_clean_timeseries_encoding_and_line_endings():
    file_path = "/home/user/workspace/clean_timeseries.csv"

    # Check if it's valid UTF-8 by reading it
    try:
        with open(file_path, "rb") as f:
            raw_data = f.read()
            text_data = raw_data.decode("utf-8")
    except UnicodeDecodeError:
        pytest.fail("The file clean_timeseries.csv is not valid UTF-8.")

    # Check for Unix-style line endings (LF)
    assert b"\r\n" not in raw_data, "The file contains Windows-style (CRLF) line endings instead of Unix-style (LF)."

def test_clean_timeseries_content():
    file_path = "/home/user/workspace/clean_timeseries.csv"

    with open(file_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "Year,Month,Date,City,Metric,Value",
        "2023,01,2023-01-15,Moscow,Humidity,80",
        "2023,01,2023-01-15,NewYork,Temperature,5.2",
        "2023,01,2023-01-15,Paris,Temperature,6.5",
        "2023,01,2023-01-15,Tokyo,Temperature,8.1",
        "2023,02,2023-02-20,Moscow,Humidity,75",
        "2023,02,2023-02-20,NewYork,Temperature,6.1",
        "2023,02,2023-02-20,Paris,Temperature,7.0",
        "2023,02,2023-02-20,Tokyo,Temperature,9.2",
        "2023,03,2023-03-10,Moscow,Humidity,60",
        "2023,03,2023-03-10,NewYork,Temperature,10.5",
        "2023,03,2023-03-10,Paris,Temperature,11.2",
        "2023,03,2023-03-10,Tokyo,Temperature,14.0"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines, but got {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected: '{expected}', Got: '{actual}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
