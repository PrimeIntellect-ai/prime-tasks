#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_raw_materials_needed_exists_and_content():
    file_path = "/home/user/raw_materials_needed.csv"

    assert os.path.exists(file_path), f"Output file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    expected_content = """name,quantity
Copper,4
Plastic,5
Silicon,8
Steel,7"""

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == expected_content, (
        f"Content of {file_path} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
