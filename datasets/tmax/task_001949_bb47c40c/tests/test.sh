#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

ORACLE_PATH = "/tests/oracle_processor"
AGENT_PATH = "/home/user/pipeline/process.py"
TEST_SUITE_PATH = "/home/user/pipeline/tests/test_processor.py"

def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_PATH), f"Agent script missing: {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script is not executable: {AGENT_PATH}"

def test_test_suite_passes():
    # The student is supposed to fix the test suite. Let's run pytest on it.
    result = subprocess.run(
        ["pytest", TEST_SUITE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    assert result.returncode == 0, f"Test suite did not pass. Output:\n{result.stdout}\n{result.stderr}"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing: {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle not executable: {ORACLE_PATH}"

    random.seed(42)
    N = 10000

    inputs = []
    current_ts = 0
    for _ in range(N):
        delta = random.randint(50, 400)
        current_ts += delta
        x = random.randint(-5000, 5000)
        inputs.append(f"{current_ts} {x}")

    input_str = "\n".join(inputs) + "\n"

    oracle_proc = subprocess.run(
        [ORACLE_PATH],
        input=input_str,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    assert oracle_proc.returncode == 0, f"Oracle failed to run:\n{oracle_proc.stderr}"
    oracle_output = oracle_proc.stdout.strip().split("\n")

    agent_proc = subprocess.run(
        [AGENT_PATH],
        input=input_str,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    assert agent_proc.returncode == 0, f"Agent script failed to run:\n{agent_proc.stderr}"
    agent_output = agent_proc.stdout.strip().split("\n")

    assert len(agent_output) == len(oracle_output), f"Output length mismatch. Expected {len(oracle_output)}, got {len(agent_output)}"

    for i, (oracle_line, agent_line) in enumerate(zip(oracle_output, agent_output)):
        assert oracle_line == agent_line, (
            f"Mismatch at line {i + 1}.\n"
            f"Input: {inputs[i]}\n"
            f"Expected (Oracle): {oracle_line}\n"
            f"Got (Agent): {agent_line}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
