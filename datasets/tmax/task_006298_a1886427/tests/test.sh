#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_max_z_file_exists():
    path = "/home/user/max_z.txt"
    assert os.path.isfile(path), f"Expected output file {path} does not exist."

def test_max_z_value_correct():
    path = "/home/user/max_z.txt"
    assert os.path.isfile(path), f"Expected output file {path} does not exist."

    with open(path, 'r') as f:
        content = f.read().strip()

    assert content == "154.2", f"Expected max Z value to be '154.2', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
