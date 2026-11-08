#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_report_file_exists():
    report_path = "/home/user/zip_slip_report.txt"
    assert os.path.isfile(report_path), f"The report file {report_path} was not created."

def test_report_content_and_encoding():
    report_path = "/home/user/zip_slip_report.txt"
    try:
        with open(report_path, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()
    except UnicodeDecodeError:
        pytest.fail(f"The report file {report_path} is not properly encoded in UTF-8.")

    # Remove any empty lines that might have been added at the end
    lines = [line.strip() for line in lines if line.strip()]

    expected_lines = [
        "arch_002_slip:504b0708deadbeef0102030405060708",
        "arch_004_slip:1f8b0800000000000203aabbccddeeff"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in the report, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{actual}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
