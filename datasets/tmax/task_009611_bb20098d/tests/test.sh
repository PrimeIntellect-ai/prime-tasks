#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_top_runs_file_exists():
    """Verify that the output file exists."""
    output_file = "/home/user/top_runs.txt"
    assert os.path.isfile(output_file), f"Expected output file {output_file} does not exist."

def test_top_runs_content():
    """Verify that the output file contains the correct top 3 run_ids in order."""
    output_file = "/home/user/top_runs.txt"

    if not os.path.exists(output_file):
        pytest.fail(f"File {output_file} is missing.")

    with open(output_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_runs = ["run_006", "run_002", "run_005"]

    assert len(lines) == 3, f"Expected exactly 3 run_ids in {output_file}, but found {len(lines)}."
    assert lines == expected_runs, f"Expected run_ids {expected_runs} in order, but got {lines}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
