#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_anomalies_file_exists():
    path = "/home/user/anomalies.txt"
    assert os.path.exists(path), f"File {path} does not exist. Did you save the output?"
    assert os.path.isfile(path), f"Path {path} is not a file."

def test_anomalies_file_content():
    path = "/home/user/anomalies.txt"
    assert os.path.exists(path), f"File {path} does not exist."

    with open(path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip()]

    expected_lines = ["103", "105"]
    assert lines == expected_lines, (
        f"Contents of {path} are incorrect. "
        f"Expected {expected_lines}, but got {lines}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
