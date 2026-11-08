#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import pytest

def test_bug_report_exists_and_correct():
    report_path = "/home/user/bug_report.txt"
    data_path = "/home/user/data_inputs.txt"

    assert os.path.isfile(data_path), f"Input data file {data_path} is missing."
    assert os.path.isfile(report_path), f"Bug report file {report_path} was not created."

    # Compute the expected values
    expected_line_num = None
    expected_diff = None

    with open(data_path, "r") as f:
        for i, line in enumerate(f, start=1):
            val_str = line.strip()
            if not val_str:
                continue
            val = float(val_str)

            # reference logic
            ref_out = round(val * 2.71828, 5)

            # suspicious logic
            if val > 500:
                susp_out = round(int(val) * 2.71828, 5)
            else:
                susp_out = round(val * 2.71828, 5)

            diff = abs(ref_out - susp_out)
            if diff > 0.1:
                expected_line_num = i
                expected_diff = round(diff, 2)
                break

    assert expected_line_num is not None, "Could not find any line with difference > 0.1 in the input data."

    expected_content = f"Line: {expected_line_num}, Diff: {expected_diff:.2f}"

    with open(report_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Contents of {report_path} are incorrect.\n"
        f"Expected: '{expected_content}'\n"
        f"Found: '{actual_content}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
