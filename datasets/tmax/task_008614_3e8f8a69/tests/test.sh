#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_recovered_evidence_exists():
    evidence_path = "/home/user/recovered_evidence.txt"
    assert os.path.exists(evidence_path), f"The file {evidence_path} does not exist."
    assert os.path.isfile(evidence_path), f"{evidence_path} is not a file."

def test_recovered_evidence_content():
    evidence_path = "/home/user/recovered_evidence.txt"
    assert os.path.exists(evidence_path), f"The file {evidence_path} does not exist."

    with open(evidence_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "Exfil from [REDACTED] started",
        "Admin creds sent to [REDACTED]",
        "C2 connect [REDACTED] port 443"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected: '{expected}', Got: '{actual}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
