#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_cleaned_max_distances_exists_and_correct():
    output_file = "/home/user/cleaned_max_distances.csv"

    assert os.path.exists(output_file), f"Expected output file {output_file} does not exist."
    assert os.path.isfile(output_file), f"Expected {output_file} to be a file."

    expected_content = """bucketed_hour,device_id,max_distance
2023-10-01T10:00:00Z,d1,2.83
2023-10-01T10:00:00Z,d2,7.07
2023-10-01T10:00:00Z,d3,2.00
2023-10-01T11:00:00Z,d1,5.00
2023-10-01T11:00:00Z,d2,5.00
2023-10-01T11:00:00Z,d3,2.83
2023-10-01T12:00:00Z,d1,1.00
2023-10-01T12:00:00Z,d2,1.00
2023-10-01T12:00:00Z,d3,5.00"""

    with open(output_file, "r") as f:
        actual_content = f.read().strip()

    actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]
    expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, "The contents of the output CSV do not match the expected results."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
