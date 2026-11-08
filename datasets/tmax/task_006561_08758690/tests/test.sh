#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_eigen_stats_output():
    file_path = "/home/user/eigen_stats.txt"

    assert os.path.isfile(file_path), f"File {file_path} does not exist. The script must create this file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_content = "Mean: 2.6667\nStdDev: 0.5774"

    assert content == expected_content, (
        f"Content of {file_path} is incorrect.\n"
        f"Expected:\n{expected_content}\n"
        f"Got:\n{content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
