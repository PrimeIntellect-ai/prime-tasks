#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/generate_audit_mac.py"
ORACLE_SCRIPT = "/tests/oracle_mac"
N_TESTS = 100
TIMEOUT = 2.0

def generate_random_string(chars, min_len, max_len):
    length = random.randint(min_len, max_len)
    return ''.join(random.choice(chars) for _ in range(length))

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_SCRIPT), f"Oracle script not found at {ORACLE_SCRIPT}"
    assert os.access(ORACLE_SCRIPT, os.X_OK), f"Oracle script is not executable"

    random.seed(42)

    alphanumeric = string.ascii_letters + string.digits
    alphabetic = string.ascii_letters

    for i in range(N_TESTS):
        username = generate_random_string(alphanumeric, 3, 15)
        role = generate_random_string(alphabetic, 4, 10)

        # Run oracle
        try:
            oracle_result = subprocess.run(
                [ORACLE_SCRIPT, username, role],
                capture_output=True,
                text=True,
                timeout=TIMEOUT,
                check=True
            )
            oracle_output = oracle_result.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input: username='{username}', role='{role}'")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input: username='{username}', role='{role}'. Error: {e.stderr}")

        # Run agent
        try:
            agent_result = subprocess.run(
                ["python3", AGENT_SCRIPT, username, role],
                capture_output=True,
                text=True,
                timeout=TIMEOUT
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input: username='{username}', role='{role}'")

        assert agent_result.returncode == 0, f"Agent script failed on input: username='{username}', role='{role}'. Stderr: {agent_result.stderr}"

        agent_output = agent_result.stdout

        assert agent_output == oracle_output, (
            f"Mismatch on input {i+1}/{N_TESTS}:\n"
            f"Username: '{username}'\n"
            f"Role: '{role}'\n"
            f"Expected (Oracle): '{oracle_output}'\n"
            f"Got (Agent): '{agent_output}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
