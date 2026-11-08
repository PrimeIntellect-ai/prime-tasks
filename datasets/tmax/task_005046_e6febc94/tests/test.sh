#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random

def test_fuzz_equivalence():
    agent_script = "/home/user/process_signal.py"
    oracle_script = "/tests/oracle_process.py"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} does not exist."

    random.seed(42)

    for i in range(100):
        # Generate 50 comma-separated floats uniformly sampled from [-3.0, 3.0]
        floats = [random.uniform(-3.0, 3.0) for _ in range(50)]
        input_str = ",".join(f"{f:.6f}" for f in floats)

        # Run oracle
        oracle_proc = subprocess.run(
            ["/usr/bin/python3", oracle_script],
            input=input_str,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}:\n{oracle_proc.stderr}"
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run(
            ["/usr/bin/python3", agent_script],
            input=input_str,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent script failed on iteration {i}:\n{agent_proc.stderr}"
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on iteration {i}.\n"
            f"Input: {input_str[:100]}...\n"
            f"Oracle output: '{oracle_out}'\n"
            f"Agent output: '{agent_out}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
