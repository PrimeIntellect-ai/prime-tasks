#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_deadlock_report_exists_and_correct():
    report_path = "/home/user/deadlock_report.txt"
    assert os.path.isfile(report_path), f"The file {report_path} does not exist."

    with open(report_path, 'r') as f:
        lines = [line.strip() for line in f.read().strip().split('\n')]

    assert len(lines) == 3, f"Expected exactly 3 lines in {report_path}, but found {len(lines)}."

    expected_line_1 = "Cluster,Snapshot,Volume"
    expected_line_2 = "BACKED_BY,HAS_SNAPSHOT,MOUNTS"
    expected_line_3 = "BACKED_BY"

    assert lines[0] == expected_line_1, f"Line 1 is incorrect. Expected '{expected_line_1}', got '{lines[0]}'."
    assert lines[1] == expected_line_2, f"Line 2 is incorrect. Expected '{expected_line_2}', got '{lines[1]}'."
    assert lines[2] == expected_line_3, f"Line 3 is incorrect. Expected '{expected_line_3}', got '{lines[2]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
