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

ORACLE_PATH = "/tests/oracle"
AGENT_PATH = "/home/user/encoder"
NUM_TESTS = 100

def generate_random_input(length):
    # Mix of letters, digits, >, newlines, and spaces
    charset = string.ascii_letters + string.digits + ">\n \t"
    return "".join(random.choice(charset) for _ in range(length))

def test_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent file at {AGENT_PATH} is not executable"

def test_fuzz_equivalence():
    random.seed(42)

    for i in range(NUM_TESTS):
        length = random.randint(0, 2000)
        input_data = generate_random_input(length)

        # Inject some explicit edge cases for the first few iterations
        if i == 0:
            input_data = ""
        elif i == 1:
            input_data = ">Header\nACGT\n>Another\nN"
        elif i == 2:
            input_data = "NNNNNNNNNN"
        elif i == 3:
            input_data = ">\n>\n>"

        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input {repr(input_data)}"

        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_data,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == 0, (
            f"Agent program crashed (return code {agent_proc.returncode}) on input {repr(input_data)}\n"
            f"Stderr: {agent_proc.stderr}"
        )

        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on test {i+1}/{NUM_TESTS}.\n"
            f"Input: {repr(input_data)}\n"
            f"Oracle output: {repr(oracle_out)}\n"
            f"Agent output: {repr(agent_out)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
