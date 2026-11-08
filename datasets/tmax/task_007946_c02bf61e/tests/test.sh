#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_clean_evidence_file_exists_and_correct():
    """Check that the clean_evidence.txt file exists and has the correctly redacted content."""
    clean_file_path = "/home/user/forensics/clean_evidence.txt"

    assert os.path.exists(clean_file_path), f"The file {clean_file_path} does not exist."
    assert os.path.isfile(clean_file_path), f"The path {clean_file_path} is not a file."

    expected_clean_text = """EVIDENCE_START
Host: web-server-01
Timestamp: 2023-10-24T08:15:32Z
Action: database_dump
Dump contents:
User: alice | Card: [REDACTED_CC] | Exp: 12/25
User: bob | Card: [REDACTED_CC] | Exp: 01/26
User: charlie | Card: [REDACTED_CC] | Exp: 08/24
Notes: Ensure logs are cleared after extraction.
END_OF_DUMP"""

    with open(clean_file_path, "r", encoding="utf-8") as f:
        actual_content = f.read()

    assert actual_content == expected_clean_text, (
        "The content of clean_evidence.txt does not match the expected redacted output. "
        "Ensure the file was decrypted correctly and all credit card numbers were redacted."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
