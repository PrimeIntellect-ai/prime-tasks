#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_best_match_file():
    file_path = '/home/user/best_match.txt'
    assert os.path.exists(file_path), f"File {file_path} does not exist. The task requires writing the best matching model name to this file."

    with open(file_path, 'r') as f:
        content = f.read().strip()

    assert content == "model_beta", f"Expected 'model_beta' in {file_path}, but got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
