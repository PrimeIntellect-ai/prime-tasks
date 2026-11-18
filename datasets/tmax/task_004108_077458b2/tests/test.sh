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

ORACLE_PATH = "/tests/oracle_encoder.py"
AGENT_SCRIPT = "/home/user/clean_encoder.py"
CHARSET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 !@#$%^&*()_+-=[]{}|;':,./<>?"
N_TESTS = 250
MIN_LEN = 1
MAX_LEN = 500

def generate_random_string(length: int) -> str:
    return ''.join(random.choice(CHARSET) for _ in range(length))

def run_script(cmd: list, input_data: str) -> str:
    try:
        result = subprocess.run(
            cmd,
            input=input_data,
            text=True,
            capture_output=True,
            check=True,
            timeout=5
        )
        return result.stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script execution failed for cmd {cmd}. Stderr: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Script execution timed out for cmd {cmd}.")

def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_PATH), f"Oracle script not found at {ORACLE_PATH}"

    random.seed(42)

    for i in range(N_TESTS):
        length = random.randint(MIN_LEN, MAX_LEN)
        input_str = generate_random_string(length)

        oracle_cmd = ["python3", ORACLE_PATH]
        agent_cmd = ["python3", AGENT_SCRIPT]

        oracle_output = run_script(oracle_cmd, input_str)
        agent_output = run_script(agent_cmd, input_str)

        if oracle_output != agent_output:
            pytest.fail(
                f"Mismatch on test {i + 1}/{N_TESTS}.\n"
                f"Input (length {length}): {repr(input_str)}\n"
                f"Oracle output: {repr(oracle_output)}\n"
                f"Agent output:  {repr(agent_output)}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
