#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

def test_process_script_exists():
    assert os.path.isfile("/home/user/process.py"), "The required script /home/user/process.py is missing."

def test_fuzz_equivalence():
    oracle_cmd = ["python3", "/tests/oracle.py"]
    agent_cmd = ["python3", "/home/user/process.py"]

    random.seed(42)
    num_tests = 500

    for i in range(num_tests):
        # Generate between 5 and 50 random floats between -10.0 and 10.0
        n = random.randint(5, 50)
        nums = [random.uniform(-10.0, 10.0) for _ in range(n)]
        input_str = " ".join(f"{x:.6f}" for x in nums)

        # Run oracle
        oracle_proc = subprocess.run(
            oracle_cmd,
            input=input_str,
            text=True,
            capture_output=True,
            check=False
        )

        # Run agent
        agent_proc = subprocess.run(
            agent_cmd,
            input=input_str,
            text=True,
            capture_output=True,
            check=False
        )

        assert agent_proc.returncode == 0, f"Agent script failed on input: {input_str}\nError: {agent_proc.stderr}"
        assert oracle_proc.returncode == 0, f"Oracle script failed on input: {input_str}\nError: {oracle_proc.stderr}"

        oracle_output = oracle_proc.stdout.strip()
        agent_output = agent_proc.stdout.strip()

        assert agent_output == oracle_output, (
            f"Output mismatch on fuzz test {i+1}/{num_tests}.\n"
            f"Input: {input_str}\n"
            f"Expected (Oracle): {oracle_output}\n"
            f"Got (Agent): {agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
