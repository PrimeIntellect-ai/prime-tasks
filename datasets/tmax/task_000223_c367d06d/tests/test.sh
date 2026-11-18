#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import string
import subprocess
import pytest

def generate_fuzz_input():
    length = random.randint(10, 200)
    chars = []
    for _ in range(length):
        choice = random.random()
        if choice < 0.15:
            # literal backslash, u, and 4 hex digits
            chars.append(f"\\u{random.randint(32, 126):04x}")
        elif choice < 0.25:
            chars.append(random.choice([' ', '\t']))
        elif choice < 0.35:
            chars.append(random.choice(['@', '#']))
        else:
            chars.append(random.choice(string.ascii_letters + string.digits + string.punctuation))
    msg = "".join(chars)
    return json.dumps({"message": msg})

def test_fuzz_equivalence():
    agent_script = "/home/user/process_log.py"
    oracle_script = "/tests/oracle.py"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"

    random.seed(42)
    num_tests = 500

    for i in range(num_tests):
        input_data = generate_fuzz_input()

        # Run oracle
        oracle_proc = subprocess.run(
            ["python3", oracle_script],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input: {input_data}\nError: {oracle_proc.stderr}"
        oracle_output = oracle_proc.stdout

        # Run agent
        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=input_data,
            text=True,
            capture_output=True
        )

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent script failed (exit code {agent_proc.returncode}) on input:\n{input_data}\nStderr:\n{agent_proc.stderr}")

        agent_output = agent_proc.stdout

        if oracle_output != agent_output:
            pytest.fail(
                f"Mismatch on fuzz iteration {i+1}!\n"
                f"Input JSON:\n{input_data}\n"
                f"Expected output (Oracle):\n{repr(oracle_output)}\n"
                f"Actual output (Agent):\n{repr(agent_output)}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
