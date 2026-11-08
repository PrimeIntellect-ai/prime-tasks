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

ORACLE_PATH = "/tests/oracle_audit"
AGENT_PATH = "/home/user/audit_tool"

def generate_random_string(length):
    return ''.join(random.choices(string.ascii_uppercase, k=length))

def generate_test_case():
    num_lines = random.randint(10, 100)
    lines = []
    for _ in range(num_lines):
        sender = generate_random_string(random.randint(1, 5))
        receiver = generate_random_string(random.randint(1, 5))
        amount = random.randint(10, 9999)
        lines.append(f"{sender},{receiver},{amount}")
    return "\n".join(lines) + "\n"

def test_agent_binary_exists_and_executable():
    assert os.path.exists(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"{AGENT_PATH} is not executable"

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle at {ORACLE_PATH} is not executable"

    random.seed(42)
    num_test_cases = 100

    for i in range(num_test_cases):
        input_data = generate_test_case()

        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_data,
            text=True,
            capture_output=True,
            check=True
        )
        oracle_output = oracle_proc.stdout

        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_data,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == 0, f"Agent program failed with return code {agent_proc.returncode}\nStderr: {agent_proc.stderr}"
        agent_output = agent_proc.stdout

        assert agent_output == oracle_output, (
            f"Output mismatch on test case {i+1}!\n"
            f"Input data:\n{input_data}\n"
            f"Expected (Oracle):\n{oracle_output}\n"
            f"Actual (Agent):\n{agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
