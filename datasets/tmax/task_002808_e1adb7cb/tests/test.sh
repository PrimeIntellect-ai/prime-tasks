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

ORACLE_PATH = "/tests/oracle_etl_cleaner.py"
AGENT_PATH = "/home/user/etl_cleaner.py"

def test_script_exists_and_executable():
    assert os.path.isfile(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script at {AGENT_PATH} is not executable"

def generate_random_input():
    length = random.randint(0, 500)
    chars = string.ascii_letters + string.digits + " "
    # Inject invalid tokens and specific lengths to ensure logic paths are hit
    invalid_tokens = ["NULL", "N/A", "UNKNOWN", "ERR", "DROP"]
    if random.random() < 0.3:
        words = random.choices(
            invalid_tokens + ["a", "ab", "abc", "abcd", "abcde", "abcdef"],
            k=random.randint(1, 20)
        )
        return " ".join(words)
    return "".join(random.choice(chars) for _ in range(length))

def run_script(script_path, input_data):
    result = subprocess.run(
        [script_path],
        input=input_data,
        text=True,
        capture_output=True
    )
    return result.stdout

def test_fuzz_equivalence():
    random.seed(42)
    N = 1000

    for i in range(N):
        input_data = generate_random_input() + "\n"

        oracle_out = run_script(ORACLE_PATH, input_data)
        agent_out = run_script(AGENT_PATH, input_data)

        assert agent_out == oracle_out, (
            f"Mismatch on iteration {i} with input: {repr(input_data)}\n"
            f"Expected (Oracle): {repr(oracle_out)}\n"
            f"Got (Agent): {repr(agent_out)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
