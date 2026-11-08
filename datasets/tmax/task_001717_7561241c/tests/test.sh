#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_crashing_payload_file():
    payload_file = '/home/user/crashing_payload.txt'
    assert os.path.isfile(payload_file), f"File {payload_file} does not exist."

    with open(payload_file, 'r') as f:
        content = f.read().strip()

    expected_payload = "eJyrVkrLz1eyUkpKLFKyUjAy11FQMigw1VEwMFAwVNJRKi0oyi9KLQaKGZkYGOsoGZrpKBmYmAAASV8Qcw=="
    assert content == expected_payload, f"Incorrect crashing payload found in {payload_file}."

def test_error_msg_file():
    error_file = '/home/user/error_msg.txt'
    assert os.path.isfile(error_file), f"File {error_file} does not exist."

    with open(error_file, 'r') as f:
        content = f.read().strip()

    expected_msg = "Singular matrix not allowed in processing pipeline"
    assert content == expected_msg, f"Incorrect error message found in {error_file}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
