#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import pytest

def test_first_bad_commit_correct():
    commit_file = "/home/user/first_bad_commit.txt"
    assert os.path.isfile(commit_file), f"File {commit_file} does not exist."

    with open(commit_file, "r") as f:
        student_commit = f.read().strip()

    repo_path = "/home/user/data_processor"
    result = subprocess.run(
        ["git", "log", "--grep=Commit 137", "--format=%H"],
        cwd=repo_path,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, "Failed to run git log to find the expected commit."
    expected_commit = result.stdout.strip()

    assert expected_commit != "", "Could not find 'Commit 137' in git history."
    assert student_commit == expected_commit, f"Expected commit hash {expected_commit}, but got {student_commit}."

def test_minimized_json_correct():
    minimized_file = "/home/user/minimized.json"
    assert os.path.isfile(minimized_file), f"File {minimized_file} does not exist."

    with open(minimized_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{minimized_file} is not a valid JSON file.")

    expected_data = {"items": [{"val": -5, "id": 73}]}
    assert data == expected_data, f"Contents of {minimized_file} do not match the expected minimized JSON."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
