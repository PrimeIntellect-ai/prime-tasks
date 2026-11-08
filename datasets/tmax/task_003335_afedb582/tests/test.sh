#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_best_model_file_exists_and_correct():
    file_path = "/home/user/best_model.txt"
    assert os.path.isfile(file_path), f"File {file_path} does not exist. The script did not create the output file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_content = "Model: C, Score: 2.7500"
    assert content == expected_content, f"Content of {file_path} is incorrect. Expected '{expected_content}', got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
