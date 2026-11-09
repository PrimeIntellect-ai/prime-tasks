#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

def test_executable_exists():
    agent_exec = "/home/user/process_spectrum"
    assert os.path.isfile(agent_exec), f"Agent executable not found at {agent_exec}"
    assert os.access(agent_exec, os.X_OK), f"Agent executable at {agent_exec} is not executable"

def test_fuzz_equivalence():
    agent_exec = "/home/user/process_spectrum"
    oracle_exec = "/tests/oracle_processor"

    assert os.path.isfile(oracle_exec), f"Oracle executable not found at {oracle_exec}"

    random.seed(42)
    num_tests = 1000

    for i in range(num_tests):
        length = random.randint(10, 500)
        nums = [random.uniform(-100.0, 100.0) for _ in range(length)]
        input_str = " ".join(f"{n:.6f}" for n in nums) + "\n"

        # Run oracle
        oracle_proc = subprocess.run(
            [oracle_exec],
            input=input_str,
            text=True,
            capture_output=True,
            check=True
        )
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run(
            [agent_exec],
            input=input_str,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == 0, f"Agent program failed on test {i} with stderr: {agent_proc.stderr}"
        agent_out = agent_proc.stdout.strip()

        assert agent_out == oracle_out, (
            f"Output mismatch on test {i}.\n"
            f"Input length: {length}\n"
            f"First 5 inputs: {nums[:5]}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
