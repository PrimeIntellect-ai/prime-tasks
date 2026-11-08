#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_ticket_resolution_exists():
    resolution_path = "/home/user/ticket_resolution.txt"
    assert os.path.exists(resolution_path), f"Missing required file: {resolution_path}"
    assert os.path.isfile(resolution_path), f"Expected {resolution_path} to be a file"

def test_ticket_resolution_content():
    resolution_path = "/home/user/ticket_resolution.txt"
    assert os.path.exists(resolution_path), f"Missing required file: {resolution_path}"

    with open(resolution_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "Attacker IP: 192.168.55.123",
        "Leaked Token: SUPER_SECRET_TOKEN_9942",
        "Breach Timestamp: 2023-10-25 14:32:01"
    ]

    assert len(lines) == 3, f"Expected exactly 3 lines of output, found {len(lines)}"

    assert lines[0] == expected_lines[0], f"First line incorrect. Expected '{expected_lines[0]}', got '{lines[0]}'"
    assert lines[1] == expected_lines[1], f"Second line incorrect. Expected '{expected_lines[1]}', got '{lines[1]}'"
    assert lines[2] == expected_lines[2], f"Third line incorrect. Expected '{expected_lines[2]}', got '{lines[2]}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
