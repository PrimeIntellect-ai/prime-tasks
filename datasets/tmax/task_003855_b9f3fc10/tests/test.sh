#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def test_eigenvector_file_exists():
    file_path = '/home/user/eigenvector.txt'
    assert os.path.exists(file_path), f"Expected output file {file_path} is missing."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."


def test_eigenvector_content():
    file_path = '/home/user/eigenvector.txt'
    assert os.path.exists(file_path), f"Expected output file {file_path} is missing."

    with open(file_path, 'r') as f:
        content = f.read().strip()

    expected = "0.0752,-0.0022,0.9972"
    assert content == expected, f"Expected eigenvector '{expected}', but got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
