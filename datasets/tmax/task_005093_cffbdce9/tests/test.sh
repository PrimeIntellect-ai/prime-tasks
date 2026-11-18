#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import pytest

REPORT_PATH = "/home/user/debugging_report.txt"
REPO_DIR = "/home/user/data_pipeline"

def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing. Did you write your findings?"

def test_report_content():
    # Retrieve the expected commit hash dynamically from the git repository
    result = subprocess.run(
        ["git", "log", "--grep=Update 105", "--format=%H"],
        cwd=REPO_DIR,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, "Failed to run git command to retrieve the expected hash."
    expected_hash = result.stdout.strip()
    assert expected_hash, "Could not find the expected commit 'Update 105' in the repository history."

    expected_secret = "DATA_CORP_API_99XQ2"

    with open(REPORT_PATH, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) >= 2, f"Report file {REPORT_PATH} must contain at least two lines."

    actual_hash = lines[0].strip()
    actual_secret = lines[1].strip()

    assert actual_hash == expected_hash, (
        f"Line 1 (commit hash) mismatch.\n"
        f"Expected: {expected_hash}\n"
        f"Got:      {actual_hash}"
    )
    assert actual_secret == expected_secret, (
        f"Line 2 (API key) mismatch.\n"
        f"Expected: {expected_secret}\n"
        f"Got:      {actual_secret}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
