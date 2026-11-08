#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_result_file_exists_and_correct():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"File not found: {result_path}"

    with open(result_path, 'r') as f:
        content = f.read().strip()

    expected_content = "Seq_02,300.203797"
    assert content == expected_content, (
        f"Incorrect content in {result_path}. "
        f"Expected '{expected_content}', but got '{content}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
