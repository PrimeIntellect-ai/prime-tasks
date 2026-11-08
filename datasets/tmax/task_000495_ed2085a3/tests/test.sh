#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_bottleneck_analysis_result():
    result_file = "/home/user/bottleneck_analysis.txt"

    assert os.path.exists(result_file), f"The file {result_file} was not created."
    assert os.path.isfile(result_file), f"{result_file} is not a regular file."

    with open(result_file, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert content == "orders", (
        f"Incorrect bottleneck table identified. "
        f"Expected 'orders', but found '{content}' in {result_file}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
