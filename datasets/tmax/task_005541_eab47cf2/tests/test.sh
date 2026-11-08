#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_verified_sessions_file():
    target_file = "/home/user/verified_sessions.txt"

    assert os.path.exists(target_file), f"The file {target_file} was not created."
    assert os.path.isfile(target_file), f"The path {target_file} is not a file."

    with open(target_file, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip()]

    expected_lines = ["alpha_101", "delta_404"]

    assert lines == expected_lines, (
        f"The contents of {target_file} do not match the expected valid sessions.\n"
        f"Expected: {expected_lines}\n"
        f"Found: {lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
