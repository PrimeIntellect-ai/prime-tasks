#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_output_csv_exists_and_correct():
    output_file = "/home/user/output.csv"

    # Check if the output file exists
    assert os.path.exists(output_file), f"The file {output_file} is missing. Did you write the output?"
    assert os.path.isfile(output_file), f"The path {output_file} is not a file."

    # Expected content based on the truth data
    expected_content = """id,val1,val2,val3
1,10.0,20.0,5.5
2,12.0,21.0,6.1
3,11.0,20.5,5.8
4,100.0,200.0,50.0
5,105.0,195.0,49.0
6,102.0,198.0,49.0
7,10.5,20.2,5.8"""

    with open(output_file, "r") as f:
        actual_content = f.read().strip()

    # Compare actual output with expected output
    assert actual_content == expected_content.strip(), (
        f"The content of {output_file} does not match the expected state.\n"
        f"Expected:\n{expected_content.strip()}\n\n"
        f"Actual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
