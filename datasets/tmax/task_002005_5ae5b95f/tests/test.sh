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

ORACLE_PATH = "/app/legacy_hasher"
AGENT_SCRIPT = "/home/user/hasher.py"
NUM_TESTS = 200

def generate_random_path(length):
    chars = string.ascii_letters + string.digits + "/-_."
    return "".join(random.choice(chars) for _ in range(length))

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing: {ORACLE_PATH}"
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing: {AGENT_SCRIPT}"

    random.seed(42)
    inputs = [generate_random_path(random.randint(1, 256)) for _ in range(NUM_TESTS)]

    # Also include some edge cases
    inputs.extend([
        "/",
        "/mnt/data",
        "home",
        "a" * 256
    ])

    for test_input in inputs:
        # Run oracle
        oracle_cmd = [ORACLE_PATH, test_input]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on input: {test_input}"
        oracle_out = oracle_res.stdout

        # Run agent
        agent_cmd = ["python3", AGENT_SCRIPT, test_input]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

        if agent_res.returncode != 0:
            pytest.fail(f"Agent script failed (exit code {agent_res.returncode}) on input: {test_input}\nStderr: {agent_res.stderr}")

        agent_out = agent_res.stdout

        if agent_out != oracle_out:
            pytest.fail(
                f"Mismatch on input: {test_input}\n"
                f"Oracle output: {repr(oracle_out)}\n"
                f"Agent output:  {repr(agent_out)}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
