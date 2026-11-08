#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import pytest

def test_bad_commit_hash():
    output_file = "/home/user/bad_commit_hash.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."

    with open(output_file, "r") as f:
        actual_commit = f.read().strip()

    # Recompute the expected bad commit from the git history
    repo_dir = "/home/user/data_pipeline"
    assert os.path.isdir(repo_dir), f"Repository directory {repo_dir} does not exist."

    result = subprocess.run(
        ["git", "log", "--format=%H", "--grep=Update build script with security check"],
        cwd=repo_dir,
        capture_output=True,
        text=True,
        check=True
    )
    expected_commit = result.stdout.strip()

    assert expected_commit, "Could not find the expected bad commit in git history."
    assert actual_commit == expected_commit, f"Expected bad commit hash {expected_commit}, but got {actual_commit}."

def test_rejected_ip():
    output_file = "/home/user/rejected_ip.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."

    with open(output_file, "r") as f:
        actual_ip = f.read().strip()

    expected_ip = "192.168.13.37"
    assert actual_ip == expected_ip, f"Expected rejected IP {expected_ip}, but got {actual_ip}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
