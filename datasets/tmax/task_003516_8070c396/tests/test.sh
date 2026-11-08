#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

def test_bad_commit_hash_file():
    repo_dir = "/home/user/trade_pipeline"
    bad_commit_file = "/home/user/bad_commit.txt"

    assert os.path.exists(bad_commit_file), f"File {bad_commit_file} does not exist. The task requires writing the bad commit hash to this file."

    try:
        expected_hash = subprocess.check_output(
            ["git", "log", "--grep=Optimize memory usage by downcasting accumulators", "--format=%H"],
            cwd=repo_dir,
            text=True,
            stderr=subprocess.STDOUT
        ).strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to retrieve expected bad commit hash from git repository: {e.output}")

    assert expected_hash != "", "Could not find the expected bad commit in git history."

    with open(bad_commit_file, "r") as f:
        actual_hash = f.read().strip()

    assert actual_hash == expected_hash, f"Incorrect commit hash in {bad_commit_file}. Expected {expected_hash}, but got {actual_hash}."

def test_culprit_variable_file():
    culprit_file = "/home/user/culprit_variable.txt"

    assert os.path.exists(culprit_file), f"File {culprit_file} does not exist. The task requires writing the culprit variable name to this file."

    with open(culprit_file, "r") as f:
        actual_variable = f.read().strip()

    assert actual_variable == "total_exposure", f"Incorrect variable name in {culprit_file}. Expected 'total_exposure', but got '{actual_variable}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
