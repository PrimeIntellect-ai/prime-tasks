#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_simulate_script_fuzz_equivalence():
    """Test that the agent's simulate.sh behaves identically to the oracle on random inputs."""
    agent_script = "/home/user/simulate.sh"
    oracle_script = "/tests/oracle.py"

    assert os.path.exists(agent_script), f"Missing required file: {agent_script}"
    assert os.path.isfile(agent_script), f"Path is not a file: {agent_script}"
    assert os.access(agent_script, os.X_OK), f"File is not executable: {agent_script}"

    assert os.path.exists(oracle_script), f"Missing oracle file: {oracle_script}"
    assert os.access(oracle_script, os.X_OK), f"Oracle is not executable: {oracle_script}"

    random.seed(42)
    states = ['S1', 'S2', 'S3', 'S4']

    for _ in range(100):
        init_state = random.choice(states)
        num_floats = random.randint(5, 15)
        floats = []
        for _ in range(num_floats):
            while True:
                val = round(random.uniform(0.0001, 0.9999), 4)
                val_int = int(round(val * 10000))
                # Avoid exact multiples of 0.1 to prevent floating point precision edge cases
                if val_int % 1000 != 0:
                    break
            floats.append(str(val))

        args = [init_state] + floats

        oracle_cmd = [oracle_script] + args
        agent_cmd = [agent_script] + args

        oracle_proc = subprocess.run(oracle_cmd, capture_output=True, text=True)
        agent_proc = subprocess.run(agent_cmd, capture_output=True, text=True)

        assert oracle_proc.returncode == 0, f"Oracle failed on input: {' '.join(args)}\nStderr: {oracle_proc.stderr}"
        assert agent_proc.returncode == 0, f"Agent script failed on input: {' '.join(args)}\nStderr: {agent_proc.stderr}"

        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Output mismatch on input: {' '.join(args)}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent):       {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
