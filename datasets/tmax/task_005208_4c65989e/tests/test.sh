#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import string
import pytest

ORACLE_PATH = "/app/telemetry_sender"
AGENT_SCRIPT = "/home/user/emulator.py"
NUM_ITERATIONS = 500

def generate_random_input(length):
    chars = string.ascii_letters + string.digits
    return ''.join(random.choice(chars) for _ in range(length))

def test_emulator_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"The agent script {AGENT_SCRIPT} does not exist."

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary {ORACLE_PATH} is missing."
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary {ORACLE_PATH} is not executable."
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} is missing."

    random.seed(42)  # Fixed seed for reproducibility

    for i in range(NUM_ITERATIONS):
        input_len = random.randint(8, 32)
        test_input = generate_random_input(input_len)

        # Run oracle
        try:
            oracle_res = subprocess.run(
                [ORACLE_PATH, test_input],
                capture_output=True,
                text=True,
                timeout=2
            )
            oracle_output = oracle_res.stdout
        except Exception as e:
            pytest.fail(f"Failed to run oracle on input '{test_input}': {e}")

        # Run agent
        try:
            agent_res = subprocess.run(
                ["python3", AGENT_SCRIPT, test_input],
                capture_output=True,
                text=True,
                timeout=2
            )
            agent_output = agent_res.stdout
        except Exception as e:
            pytest.fail(f"Failed to run agent script on input '{test_input}': {e}")

        # Assert equivalence
        assert oracle_output == agent_output, (
            f"Mismatch on iteration {i+1} with input: '{test_input}'\n"
            f"Oracle output: {repr(oracle_output)}\n"
            f"Agent output:  {repr(agent_output)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
