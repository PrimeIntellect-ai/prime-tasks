#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

def test_report_file_exists():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"The file {report_path} does not exist. The task requires creating this report."

def test_report_contents():
    report_path = "/home/user/report.txt"
    repo_path = "/home/user/db_engine"

    # Retrieve the expected commit hash dynamically
    result = subprocess.run(
        ["git", "log", "--format=%H", "--grep=Optimize WAL processing"],
        cwd=repo_path,
        capture_output=True,
        text=True
    )
    expected_hash = result.stdout.strip()
    assert expected_hash, "Could not find the expected commit hash in the git repository."

    expected_pass = "X9T2mPqL_992"
    expected_val = "super_admin_99"

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"The report must contain exactly 3 non-empty lines, but found {len(lines)}."

    actual_hash = lines[0]
    actual_pass = lines[1]
    actual_val = lines[2]

    assert actual_hash == expected_hash, (
        f"Line 1 (commit hash) is incorrect.\n"
        f"Expected: {expected_hash}\n"
        f"Found:    {actual_hash}"
    )

    assert actual_pass == expected_pass, (
        f"Line 2 (RECOVERY_PASS) is incorrect.\n"
        f"Expected: {expected_pass}\n"
        f"Found:    {actual_pass}"
    )

    assert actual_val == expected_val, (
        f"Line 3 (ADMIN_USER value) is incorrect.\n"
        f"Expected: {expected_val}\n"
        f"Found:    {actual_val}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
