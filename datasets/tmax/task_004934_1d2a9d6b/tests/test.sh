#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_report_content():
    report_path = "/home/user/cred_rotation/report.txt"
    assert os.path.isfile(report_path), f"Security report not found at {report_path}."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines()]

    # Remove trailing empty lines if any, but keep internal structure
    while lines and not lines[-1]:
        lines.pop()

    assert len(lines) >= 2, "report.txt must contain exactly two lines (CWE and decrypted password)."

    expected_cwe = "CWE-327"
    expected_password = "MASTER_p4ssw0rd_99"

    assert lines[0] == expected_cwe, f"Line 1 of report.txt is incorrect. Expected '{expected_cwe}', got '{lines[0]}'."
    assert lines[1] == expected_password, f"Line 2 of report.txt is incorrect. Expected decrypted password '{expected_password}', got '{lines[1]}'."

def test_redacted_log_content():
    original_log_path = "/home/user/cred_rotation/rotation.log"
    redacted_log_path = "/home/user/cred_rotation/rotation_redacted.log"

    assert os.path.isfile(original_log_path), f"Original log missing at {original_log_path}. Cannot verify redaction."
    assert os.path.isfile(redacted_log_path), f"Redacted log not found at {redacted_log_path}."

    # Derive expected redacted lines from the original log
    with open(original_log_path, "r") as f:
        original_lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = []
    for line in original_lines:
        # Original format: [YYYY-MM-DD] <email> rotated password to <password>
        # We extract the date component to construct the expected redacted line dynamically.
        if "]" in line:
            date_part = line.split("]")[0] + "]"
            expected_lines.append(f"{date_part} [REDACTED_EMAIL] rotated password to [REDACTED_CRED]")
        else:
            # Fallback if original log gets corrupted, though test_initial_state checks it
            expected_lines.append(line)

    with open(redacted_log_path, "r") as f:
        redacted_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(redacted_lines) == len(expected_lines), f"Redacted log line count ({len(redacted_lines)}) does not match original log line count ({len(expected_lines)})."

    for i, (expected, actual) in enumerate(zip(expected_lines, redacted_lines)):
        assert actual == expected, f"Line {i+1} in redacted log is incorrect.\nExpected: {expected}\nGot:      {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
