#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_cleaned_data_correct():
    file_path = "/home/user/cleaned_data.csv"

    assert os.path.exists(file_path), f"Expected output file {file_path} does not exist."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."

    expected_content = (
        "2.0,4.0,A_α\n"
        "4.0,8.0,B_β\n"
        "8.0,6.0,D_δ\n"
        "10.0,0.0,E_ε\n"
    )

    with open(file_path, "r", encoding="utf-8") as f:
        actual_content = f.read()

    # Strip trailing whitespace from both to be forgiving about trailing newlines,
    # but ensure the core content matches exactly.
    assert actual_content.strip() == expected_content.strip(), (
        f"Content of {file_path} does not match expected output.\n"
        f"Expected:\n{expected_content.strip()}\n"
        f"Got:\n{actual_content.strip()}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
