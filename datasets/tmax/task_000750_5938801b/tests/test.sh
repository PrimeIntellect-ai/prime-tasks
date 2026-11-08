#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_kl"
    agent_script = "/home/user/compute_kl.py"

    assert os.path.isfile(oracle_path), f"Oracle not found at {oracle_path}"
    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"

    random.seed(42)
    num_fuzz_cases = 100

    for i in range(num_fuzz_cases):
        num_elements = random.randint(5, 25)

        # Inject edge cases
        if i % 10 == 0:
            # All zeros to test clamping and normalization
            elements = [0.0] * num_elements
        else:
            elements = [random.uniform(0.0, 100.0) for _ in range(num_elements)]

        # Randomly inject very small values to test 1e-9 clamping
        for j in range(num_elements):
            if random.random() < 0.1:
                elements[j] = random.uniform(0.0, 1e-10)

        input_arg = ",".join(f"{x:.8f}" for x in elements)

        # Run oracle
        oracle_cmd = ["python3", oracle_path, input_arg]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on input: {input_arg}\nStderr: {oracle_res.stderr}"
        oracle_out = oracle_res.stdout.strip()

        # Run agent
        agent_cmd = ["python3", agent_script, input_arg]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on input: {input_arg}\nStderr: {agent_res.stderr}"
        agent_out = agent_res.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on fuzz case {i+1}/{num_fuzz_cases}.\n"
            f"Input: {input_arg}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
