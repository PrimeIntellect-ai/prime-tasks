#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat
import hashlib
import pytest

def test_report_exists_and_correct():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"The report file {report_path} was not created."

    bin_dir = "/home/user/investigation/bin/"
    suid_binary = None
    for filename in os.listdir(bin_dir):
        filepath = os.path.join(bin_dir, filename)
        if os.path.isfile(filepath):
            st = os.stat(filepath)
            if st.st_mode & stat.S_ISUID:
                suid_binary = filepath
                break

    assert suid_binary is not None, "No SUID binary found in the investigation directory."

    log_path = "/home/user/investigation/auth.log"
    timestamp = None
    with open(log_path, "r") as f:
        for line in f:
            if "custom_suid_audit" in line and suid_binary in line:
                # Extract timestamp (first 3 tokens: Month Day Time)
                parts = line.split()
                if len(parts) >= 3:
                    timestamp = f"{parts[0]} {parts[1]} {parts[2]}"
                break

    assert timestamp is not None, "Could not find the execution timestamp in the auth.log."

    # Compute hash of SUID binary
    sha256 = hashlib.sha256()
    with open(suid_binary, "rb") as f:
        sha256.update(f.read())
    computed_hash = sha256.hexdigest()

    # Read hashes.sha256 to check for match
    hashes_path = "/home/user/investigation/hashes.sha256"
    hash_match = "FALSE"
    with open(hashes_path, "r") as f:
        for line in f:
            if suid_binary in line:
                recorded_hash = line.split()[0]
                if recorded_hash == computed_hash:
                    hash_match = "TRUE"
                break

    expected_lines = [
        f"BINARY={suid_binary}",
        f"TIMESTAMP={timestamp}",
        f"HASH_MATCH={hash_match}"
    ]

    with open(report_path, "r") as f:
        actual_content = f.read().strip().splitlines()

    # Strip trailing/leading spaces from actual lines just in case
    actual_lines = [line.strip() for line in actual_content if line.strip()]

    assert len(actual_lines) == 3, f"Expected exactly 3 lines in {report_path}, found {len(actual_lines)}."

    assert actual_lines[0] == expected_lines[0], f"First line is incorrect. Expected '{expected_lines[0]}', got '{actual_lines[0]}'."
    assert actual_lines[1] == expected_lines[1], f"Second line is incorrect. Expected '{expected_lines[1]}', got '{actual_lines[1]}'."
    assert actual_lines[2] == expected_lines[2], f"Third line is incorrect. Expected '{expected_lines[2]}', got '{actual_lines[2]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
