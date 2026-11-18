#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_smoothed_wide_csv_exists_and_correct():
    file_path = "/home/user/smoothed_wide.csv"

    assert os.path.exists(file_path), f"The expected output file {file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    expected_content = """timestamp,alpha,beta,gamma
1,10.0,20.0,30.0
2,15.0,25.0,35.0
3,20.0,30.0,40.0
4,20.0,30.0,40.0
5,20.0,26.7,33.3"""

    with open(file_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"The contents of {file_path} are incorrect.\n"
        f"Expected:\n{expected_content}\n\n"
        f"Got:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
