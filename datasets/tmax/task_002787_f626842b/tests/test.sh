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

def test_sanitize_input_recovered():
    target_path = "/home/user/sanitize_input.py"
    assert os.path.isfile(target_path), f"Expected recovered file {target_path} does not exist."

def test_fast_collatz_exists():
    target_path = "/home/user/fast_collatz.py"
    assert os.path.isfile(target_path), f"Expected script {target_path} does not exist."

def generate_fuzz_inputs(n=1000, seed=42):
    random.seed(seed)
    inputs = []
    for _ in range(n):
        num = random.randint(1, 1000000)
        s = str(num)

        # Add random corruptions
        if random.random() < 0.5:
            prefix = "".join(random.choices(string.ascii_letters + " ,.\", k=random.randint(1, 5)))
            s = prefix + s
        if random.random() < 0.5:
            suffix = "".join(random.choices(string.ascii_letters + " ,.\", k=random.randint(1, 5)))
            s = s + suffix

        inputs.append(s)
    return inputs

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_collatz"
    agent_script = "/home/user/fast_collatz.py"

    assert os.path.isfile(oracle_path), f"Oracle {oracle_path} missing."
    assert os.access(oracle_path, os.X_OK), f"Oracle {oracle_path} not executable."

    inputs = generate_fuzz_inputs(n=1000)
    expected_outputs = []

    for inp in inputs:
        oracle_proc = subprocess.run(
            [oracle_path, inp],
            capture_output=True,
            text=True,
            timeout=5
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input {repr(inp)}"
        expected_outputs.append(oracle_proc.stdout.strip())

    # Do not leave the oracle available while executing the submitted artifact.
    os.remove(oracle_path)

    for i, (inp, oracle_out) in enumerate(zip(inputs, expected_outputs)):
        agent_proc = subprocess.run(
            ["python3", agent_script, inp],
            capture_output=True,
            text=True,
            timeout=5
        )
        assert agent_proc.returncode == 0, f"Agent script failed on input {repr(inp)}\nStderr: {agent_proc.stderr}"
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on input {repr(inp)} (test {i+1}/1000).\n"
            f"Oracle output: {repr(oracle_out)}\n"
            f"Agent output: {repr(agent_out)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
