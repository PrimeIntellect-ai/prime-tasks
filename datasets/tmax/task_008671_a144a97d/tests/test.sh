#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import pytest

def test_investigation_report_exists_and_correct():
    report_path = "/home/user/investigation_report.txt"
    payload_path = "/home/user/payload.bin"

    assert os.path.isfile(report_path), f"File {report_path} is missing."

    with open(report_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {report_path}, found {len(lines)}."

    # Line 1: CWE ID
    assert lines[0] == "CWE-328", f"Line 1 is incorrect. Expected 'CWE-328', got '{lines[0]}'."

    # Line 2: Cracked PIN
    assert lines[1] == "8147", f"Line 2 is incorrect. Expected '8147', got '{lines[1]}'."

    # Line 3: Computed SHA-256
    # Let's derive it from the actual payload file to be robust
    assert os.path.isfile(payload_path), f"File {payload_path} is missing."
    with open(payload_path, 'rb') as f:
        payload_bytes = f.read()

    expected_hash = hashlib.sha256(b'8147' + payload_bytes).hexdigest()
    assert lines[2] == expected_hash, f"Line 3 is incorrect. Expected '{expected_hash}', got '{lines[2]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
