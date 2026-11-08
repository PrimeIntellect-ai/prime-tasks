#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

REPO_DIR = "/home/user/data_engine"
RESULT_FILE = "/home/user/bad_commit_hash.txt"

def test_result_file_exists():
    assert os.path.isfile(RESULT_FILE), f"The file {RESULT_FILE} does not exist."

def test_correct_bad_commit_identified():
    # Read the actual hash from the result file
    with open(RESULT_FILE, "r") as f:
        actual_hash = f.read().strip()

    assert len(actual_hash) == 40, f"The hash in {RESULT_FILE} must be exactly 40 characters long."

    # Get the expected hash (the 142nd commit in chronological order)
    try:
        result = subprocess.run(
            ["git", "rev-list", "--reverse", "HEAD"],
            cwd=REPO_DIR,
            capture_output=True,
            text=True,
            check=True
        )
        commits = result.stdout.splitlines()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to get git commit list: {e}")

    assert len(commits) >= 142, "The repository does not have at least 142 commits."
    expected_hash = commits[141]  # 0-indexed, so 141 is the 142nd commit

    assert actual_hash == expected_hash, (
        f"Incorrect commit hash identified.\n"
        f"Expected: {expected_hash}\n"
        f"Actual:   {actual_hash}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
