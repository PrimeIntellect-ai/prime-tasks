#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_audit_trail_exists_and_correct():
    file_path = "/home/user/audit_trail.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read()

    # Process actual lines: strip trailing whitespace
    actual_lines = [line.rstrip() for line in content.splitlines()]

    # Remove trailing empty lines from actual output
    while actual_lines and actual_lines[-1] == "":
        actual_lines.pop()

    expected_lines = [
        "[CWE]",
        "CWE-601",
        "",
        "[Malicious Redirects]",
        "http://evil.phishing.com/steal",
        "https://attacker.net/drop",
        "http://trusted.com/http_downgrade",
        "",
        "[Weak SSH Users]",
        "bob@legacy-system",
        "service-account-old"
    ]

    assert actual_lines == expected_lines, (
        f"The content of {file_path} does not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
