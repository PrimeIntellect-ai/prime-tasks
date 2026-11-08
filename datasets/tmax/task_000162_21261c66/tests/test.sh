#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_compromised_ips_file_exists():
    path = "/home/user/compromised_ips.txt"
    assert os.path.isfile(path), f"The file {path} does not exist. Did you save your output?"

def test_compromised_ips_content():
    path = "/home/user/compromised_ips.txt"
    assert os.path.isfile(path), f"The file {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip().splitlines()

    # The expected IPs, alphabetically sorted
    expected_ips = [
        "192.168.1.205",
        "192.168.1.50"
    ]

    assert content == expected_ips, (
        f"The contents of {path} are incorrect.\n"
        f"Expected:\n{chr(10).join(expected_ips)}\n\n"
        f"Got:\n{chr(10).join(content)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
