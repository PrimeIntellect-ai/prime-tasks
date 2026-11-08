#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_clean_rolling_avg_file_exists():
    output_file_path = "/home/user/clean_rolling_avg.csv"
    assert os.path.exists(output_file_path), f"Output file is missing: {output_file_path}"
    assert os.path.isfile(output_file_path), f"Path is not a file: {output_file_path}"

def test_clean_rolling_avg_content_and_encoding():
    output_file_path = "/home/user/clean_rolling_avg.csv"

    # Verify the file is UTF-8 encoded
    try:
        with open(output_file_path, "rb") as f:
            raw_bytes = f.read()
            decoded_content = raw_bytes.decode('utf-8')
    except UnicodeDecodeError as e:
        pytest.fail(f"Failed to decode {output_file_path} as UTF-8: {e}")
    except Exception as e:
        pytest.fail(f"Failed to read {output_file_path}: {e}")

    # Expected content
    expected_lines = [
        "device_id,timestamp,value,rolling_avg",
        "D1,2023-10-01T10:00:00Z,10,10.00",
        "D1,2023-10-01T10:01:00Z,15,12.50",
        "D1,2023-10-01T10:02:00Z,20,15.00",
        "D1,2023-10-01T10:03:00Z,25,20.00",
        "D2,2023-10-01T10:00:00Z,100,100.00",
        "D2,2023-10-01T10:02:00Z,200,150.00",
        "D2,2023-10-01T10:05:00Z,150,150.00",
        "D2,2023-10-01T10:06:00Z,300,216.67"
    ]

    actual_lines = [line.strip() for line in decoded_content.strip().splitlines()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines, but found {len(actual_lines)}. Did you remove duplicates correctly?"

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
