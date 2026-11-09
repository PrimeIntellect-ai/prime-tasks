#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import subprocess
import pytest


def test_analysis_file_contents():
    """Test that analysis.txt contains the correct findings."""
    analysis_file = "/home/user/analysis.txt"
    assert os.path.isfile(analysis_file), f"Analysis file missing: {analysis_file}"

    with open(analysis_file, "r") as f:
        lines = [line.strip() for line in f.read().strip().splitlines()]

    assert len(lines) >= 3, f"Expected at least 3 lines in {analysis_file}, found {len(lines)}"

    # Line 1: PID with most records (Worker B -> 2088)
    assert lines[0] == "2088", f"Line 1 should be '2088', got '{lines[0]}'"

    # Line 2: Duplicated record ID
    assert lines[1] == "REQ-0077", f"Line 2 should be 'REQ-0077', got '{lines[1]}'"

    # Line 3: Bottleneck record ID
    assert lines[2] == "REQ-0042", f"Line 3 should be 'REQ-0042', got '{lines[2]}'"


def test_fixed_worker_script_exists_and_executable():
    """Test that fixed_worker.sh exists and is executable."""
    script_file = "/home/user/fixed_worker.sh"
    assert os.path.isfile(script_file), f"Fixed worker script missing: {script_file}"
    assert os.access(script_file, os.X_OK), f"Fixed worker script is not executable: {script_file}"


def test_fixed_worker_concurrency():
    """Test safe concurrent processing using an unpredictable set of records."""
    script_file = "/home/user/fixed_worker.sh"
    queue_file = "/home/user/data/queue.txt"
    completed_file = "/home/user/data/completed.txt"

    # Use 100 unpredictable, unique REQ-XXXX records so the worker must consume
    # the actual queue rather than emit a fixed known answer.
    ids = secrets.SystemRandom().sample(range(1000, 10000), 100)
    records = [f"REQ-{value:04d}" for value in ids]

    with open(queue_file, "w") as f:
        for record in records:
            f.write(record + "\n")

    if os.path.exists(completed_file):
        os.remove(completed_file)

    processes = [subprocess.Popen([script_file]) for _ in range(5)]
    for process in processes:
        process.wait(timeout=30)
        assert process.returncode == 0, f"Worker exited with status {process.returncode}"

    assert os.path.isfile(completed_file), f"Completed file missing: {completed_file}"

    with open(completed_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 100, f"Expected exactly 100 lines in {completed_file}, got {len(lines)}"

    unique_lines = set(lines)
    assert len(unique_lines) == 100, f"Expected 100 unique lines, but found duplicates. Unique count: {len(unique_lines)}"

    for record in records:
        expected_line = f"{record} processed"
        assert expected_line in unique_lines, f"Missing expected output: '{expected_line}'"

    with open(queue_file, "r") as f:
        assert f.read() == "", "Queue was not fully consumed"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
