#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_debug_report_exists_and_correct():
    path = "/home/user/debug_report.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    assert os.path.isfile(path), f"Path {path} is not a file."

    with open(path, "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) >= 3, f"File {path} does not contain enough lines. Expected 3 lines."

    assert content[0].strip() == "IP: 172.16.0.42", f"First line is incorrect. Expected 'IP: 172.16.0.42', got '{content[0]}'."
    assert content[1].strip() == "PAYLOAD: CMD_VORTEX_8821", f"Second line is incorrect. Expected 'PAYLOAD: CMD_VORTEX_8821', got '{content[1]}'."
    assert content[2].strip() == "FUNCTION: _Z31execute_cmd_vortex_8821_routinev", f"Third line is incorrect. Expected 'FUNCTION: _Z31execute_cmd_vortex_8821_routinev', got '{content[2]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
