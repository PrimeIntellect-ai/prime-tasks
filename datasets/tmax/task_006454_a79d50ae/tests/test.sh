#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_report_csv_exists_and_correct():
    report_path = "/home/user/report.csv"

    assert os.path.exists(report_path), f"The file {report_path} does not exist."
    assert os.path.isfile(report_path), f"The path {report_path} is not a regular file."

    with open(report_path, 'r') as f:
        lines = f.read().strip().splitlines()

    assert len(lines) == 1, f"Expected exactly 1 line in {report_path}, but found {len(lines)}."

    expected_content = "node-service,8002,1002,1099"
    actual_content = lines[0].strip()

    assert actual_content == expected_content, (
        f"Incorrect report content. Expected '{expected_content}', but got '{actual_content}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
