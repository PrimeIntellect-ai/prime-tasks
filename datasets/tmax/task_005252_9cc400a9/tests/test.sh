#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/solution.sh"
ORACLE_BIN = "/tests/oracle_bin"
FUZZ_N = 100

def test_solution_script_exists_and_executable():
    assert os.path.exists(AGENT_SCRIPT), f"The script {AGENT_SCRIPT} does not exist."
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"{AGENT_SCRIPT} is not executable."

def generate_fuzz_input():
    num_ints = random.randint(1, 1000)
    ints = [str(random.randint(-10000, 10000)) for _ in range(num_ints)]
    return " ".join(ints)

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_BIN), f"Oracle binary {ORACLE_BIN} is missing."
    assert os.access(ORACLE_BIN, os.X_OK), f"Oracle binary {ORACLE_BIN} is not executable."

    random.seed(42)  # Fixed seed for reproducibility

    for i in range(FUZZ_N):
        test_input = generate_fuzz_input()
        input_bytes = (test_input + "\n").encode("utf-8")

        # Run Oracle
        try:
            oracle_proc = subprocess.run(
                [ORACLE_BIN],
                input=input_bytes,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
                check=True
            )
            oracle_output = oracle_proc.stdout.decode("utf-8").strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input {test_input[:50]}... with stderr: {e.stderr.decode('utf-8')}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {test_input[:50]}...")

        # Run Agent
        try:
            agent_proc = subprocess.run(
                [AGENT_SCRIPT],
                input=input_bytes,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
                check=False
            )
            agent_output = agent_proc.stdout.decode("utf-8").strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input {test_input[:50]}...")

        if agent_proc.returncode != 0:
            stderr_out = agent_proc.stderr.decode("utf-8")
            pytest.fail(f"Agent script failed (exit code {agent_proc.returncode}) on input {test_input[:50]}...\nStderr: {stderr_out}")

        assert agent_output == oracle_output, (
            f"Output mismatch on fuzz iteration {i + 1}.\n"
            f"Input (truncated): {test_input[:100]}...\n"
            f"Oracle output: {oracle_output}\n"
            f"Agent output: {agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
