#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_leak_report_content():
    report_path = "/home/user/leak_report.txt"
    assert os.path.exists(report_path), f"File {report_path} does not exist. You need to create it."

    with open(report_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_payload = "PAYLOAD_ID_9921_CORRUPT_MAGIC_0xBAADF00D"
    assert content == expected_payload, f"Expected {report_path} to contain exactly '{expected_payload}', but got '{content}'."

def test_env_file_updated():
    env_path = "/home/user/.env"
    assert os.path.exists(env_path), f"File {env_path} does not exist."

    with open(env_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Check if FLUSH_ON_ERROR=1 is present
    lines = content.splitlines()
    found = False
    for line in lines:
        line = line.strip()
        if line.startswith("FLUSH_ON_ERROR"):
            parts = line.split("=", 1)
            if len(parts) == 2 and parts[1].strip() in ["1", "'1'", '"1"']:
                found = True
                break

    assert found, f"FLUSH_ON_ERROR=1 is not correctly set in {env_path}. Make sure you updated the environment variables as requested."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
