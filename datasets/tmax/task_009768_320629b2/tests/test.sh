#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

def test_payload_enc_exists():
    payload_path = "/home/user/payload.enc"
    assert os.path.isfile(payload_path), f"The expected payload file {payload_path} does not exist."
    assert os.path.getsize(payload_path) > 0, f"The payload file {payload_path} is empty."

def test_payload_execution_and_result():
    payload_path = "/home/user/payload.enc"
    logger_path = "/home/user/target/logger.py"
    pwned_path = "/home/user/pwned.txt"

    # Ensure the payload exists before trying to run it
    assert os.path.isfile(payload_path), f"Cannot run test because {payload_path} is missing."

    # Remove pwned.txt if it exists from a previous run to ensure a clean test
    if os.path.exists(pwned_path):
        os.remove(pwned_path)

    # Run the logger script with the student's payload
    try:
        result = subprocess.run(
            ["python3", logger_path, payload_path],
            capture_output=True,
            text=True,
            timeout=5
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The logger script timed out while processing the payload.")
    except Exception as e:
        pytest.fail(f"Failed to execute the logger script: {e}")

    # Verify that the payload successfully created the target file
    assert os.path.isfile(pwned_path), (
        f"The file {pwned_path} was not created. "
        f"This indicates the payload did not successfully exploit the command injection vulnerability. "
        f"Logger stdout: {result.stdout}\nLogger stderr: {result.stderr}"
    )

    # Verify the contents of the target file
    with open(pwned_path, 'r') as f:
        content = f.read().strip()

    expected_content = "SYSTEM_COMPROMISED"
    assert content == expected_content, (
        f"The file {pwned_path} was created, but its contents are incorrect. "
        f"Expected '{expected_content}', but found '{content}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
