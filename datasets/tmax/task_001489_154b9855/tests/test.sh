#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

def test_fixed_processor_fuzz_equivalence():
    agent_script = "/home/user/fixed_processor.py"
    oracle_script = "/tests/oracle_processor"

    assert os.path.exists(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.exists(oracle_script), f"Oracle script not found at {oracle_script}"

    random.seed(42)
    N = 1000

    for _ in range(N):
        x = random.uniform(1.0, 100.0)
        y = random.uniform(-3.14, 3.14)

        x_str = f"{x:.6f}"
        y_str = f"{y:.6f}"

        # Run oracle
        oracle_cmd = [oracle_script, x_str, y_str]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on inputs {x_str}, {y_str}:\n{oracle_res.stderr}"
        oracle_out = oracle_res.stdout.strip()

        # Run agent
        agent_cmd = ["python3", agent_script, x_str, y_str]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on inputs {x_str}, {y_str}:\n{agent_res.stderr}"
        agent_out = agent_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on inputs x={x_str}, y={y_str}.\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output:  {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
