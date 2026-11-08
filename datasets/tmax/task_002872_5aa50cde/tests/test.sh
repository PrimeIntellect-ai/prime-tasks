#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import subprocess
import pytest

def test_beacon_is_running():
    """Test that the suspicious_beacon process is currently running."""
    try:
        # pgrep returns 0 if matches are found
        output = subprocess.check_output(["pgrep", "-f", "suspicious_beacon"])
        assert output.strip(), "suspicious_beacon process is not running."
    except subprocess.CalledProcessError:
        pytest.fail("suspicious_beacon process is not running. Did you start it in the background?")

def test_report_contents():
    """Test that the report.txt file contains the correct findings."""
    report_path = "/home/user/report.txt"
    assert os.path.exists(report_path), f"File {report_path} does not exist."
    assert os.path.isfile(report_path), f"Path {report_path} is not a file."

    with open(report_path, "r") as f:
        # Read lines, stripping trailing whitespace/newlines
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {report_path}, found {len(lines)}."

    expected_port = "28443"
    expected_salt = "B34C0N_S4LT_82XF9!"

    # Compute the token dynamically as specified in the task
    combined_string = f"{expected_salt}{expected_port}"
    expected_token = hashlib.sha256(combined_string.encode('utf-8')).hexdigest()

    assert lines[0] == f"PORT={expected_port}", f"Line 1 is incorrect. Expected PORT={expected_port}, got {lines[0]}"
    assert lines[1] == f"SALT={expected_salt}", f"Line 2 is incorrect. Expected SALT={expected_salt}, got {lines[1]}"
    assert lines[2] == f"TOKEN={expected_token}", f"Line 3 is incorrect. Expected TOKEN={expected_token}, got {lines[2]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
