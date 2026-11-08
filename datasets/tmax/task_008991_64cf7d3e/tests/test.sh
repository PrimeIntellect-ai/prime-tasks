#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

REPORT_FILE = "/home/user/report.txt"
REPO_DIR = "/home/user/service-repo"

def get_expected_commit():
    try:
        result = subprocess.run(
            ["git", "log", "--grep=Optimize connection closure", "--format=%H"],
            cwd=REPO_DIR,
            capture_output=True,
            text=True,
            check=True
        )
        commit = result.stdout.strip()
        if not commit:
            pytest.fail("Could not find the expected commit in git history.")
        return commit
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run git log: {e}")

def test_report_exists_and_format():
    assert os.path.isfile(REPORT_FILE), f"Report file {REPORT_FILE} is missing. You must create it."
    with open(REPORT_FILE, "r") as f:
        lines = [line.strip() for line in f.read().strip().split('\n') if line.strip() != ""]
    assert len(lines) == 3, f"Expected exactly 3 lines in {REPORT_FILE}, found {len(lines)}."

def test_report_content():
    if not os.path.isfile(REPORT_FILE):
        pytest.fail(f"Report file {REPORT_FILE} is missing.")

    with open(REPORT_FILE, "r") as f:
        lines = [line.strip() for line in f.read().strip().split('\n') if line.strip() != ""]

    if len(lines) != 3:
        pytest.fail(f"Report file {REPORT_FILE} does not have exactly 3 lines.")

    expected_token = "trk_9918273645x_alpha"
    expected_commit = get_expected_commit()
    expected_function = "close_connection"

    assert lines[0] == expected_token, f"Line 1 (token) is incorrect. Expected {expected_token}, got {lines[0]}"
    assert lines[1] == expected_commit, f"Line 2 (commit hash) is incorrect. Expected {expected_commit}, got {lines[1]}"
    assert lines[2] == expected_function, f"Line 3 (function name) is incorrect. Expected {expected_function}, got {lines[2]}"

def test_load_test_passes():
    env = os.environ.copy()
    env["TEST_AUTH_TOKEN"] = "trk_9918273645x_alpha"

    result = subprocess.run(
        ["python", "load_test.py"],
        cwd=REPO_DIR,
        env=env,
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"load_test.py failed with exit code {result.returncode}.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    assert "Success: No memory leak detected." in result.stdout, "Success message not found in load_test.py output. The memory leak might not be fully fixed."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
