#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_extraction_log():
    log_path = "/home/user/extraction.log"
    assert os.path.isfile(log_path), f"Log file is missing: {log_path}"

    expected_lines = [
        "group_A/nested/sample2.dat: DATA",
        "group_A/sample1.dat: RSCH",
        "group_B/data.dat: RSCH"
    ]

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert lines == expected_lines, f"Contents of {log_path} do not match the expected sorted output. Got: {lines}"

def test_extracted_payloads():
    bin_path = "/home/user/extracted_payloads.bin"
    assert os.path.isfile(bin_path), f"Extracted payloads file is missing: {bin_path}"

    expected_payloads = [
        b"PAYLOAD_A1_00000",
        b"HELO_WORLD",
        b"TESTING_DATA_123"
    ]

    expected_size = sum(len(p) for p in expected_payloads)
    actual_size = os.path.getsize(bin_path)
    assert actual_size == expected_size, f"File {bin_path} has incorrect size. Expected {expected_size}, got {actual_size}"

    with open(bin_path, "rb") as f:
        content = f.read()

    for payload in expected_payloads:
        assert payload in content, f"Expected payload {payload} not found in {bin_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
