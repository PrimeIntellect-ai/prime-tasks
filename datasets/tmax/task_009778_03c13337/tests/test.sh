#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_report_exists_and_correct():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"Expected report file {report_path} is missing."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 3, f"Expected at least 3 lines in {report_path}, found {len(lines)}."

    expected_line1 = "/home/user/target data copy.txt"
    expected_line2 = "M4LW4R3_K3Y_99X"
    expected_line3 = "FLAG{W4L_R3C0V3R3D}"

    assert lines[0] == expected_line1, f"Line 1 incorrect. Expected '{expected_line1}', got '{lines[0]}'."
    assert lines[1] == expected_line2, f"Line 2 incorrect. Expected '{expected_line2}', got '{lines[1]}'."
    assert lines[2] == expected_line3, f"Line 3 incorrect. Expected '{expected_line3}', got '{lines[2]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
