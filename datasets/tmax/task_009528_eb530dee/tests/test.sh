#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_recovered_evidence_exists():
    path = "/home/user/recovered_evidence.txt"
    assert os.path.isfile(path), f"File {path} does not exist. The evidence was not saved."

def test_recovered_evidence_content():
    path = "/home/user/recovered_evidence.txt"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, 'r') as f:
        content = f.read().strip()

    expected_evidence = "FLAG{h1dd3n_d4t4_r3c0v3r3d_succ3ssfully}"
    assert content == expected_evidence, f"The content of {path} is incorrect. Expected '{expected_evidence}', got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
