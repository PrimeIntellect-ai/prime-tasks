#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_bow_features_csv_exists_and_content():
    file_path = "/home/user/bow_features.csv"
    assert os.path.isfile(file_path), f"Missing file: {file_path}"

    expected_content = """id,great,price,quality
1,1,0,1
2,0,1,1
3,0,0,0
4,1,1,1
5,1,1,1"""

    with open(file_path, "r") as f:
        actual_content = f.read().strip().replace('\r', '')

    assert actual_content == expected_content, (
        f"Content of {file_path} does not match expected output.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
