#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

def test_fuzz_equivalence():
    agent_script = "/home/user/evaluator.py"
    oracle_bin = "/tests/oracle_evaluator"

    assert os.path.exists(agent_script), f"Agent script {agent_script} not found. Did you create it?"
    assert os.path.exists(oracle_bin), f"Oracle binary {oracle_bin} not found."

    random.seed(42)
    amino_acids = "ACDEFGHIKLMNPQRSTVWY"

    for i in range(200):
        length = random.randint(10, 50)
        seq = "".join(random.choice(amino_acids) for _ in range(length))
        x = random.uniform(-1000.0, 1000.0)
        y = random.uniform(-1000.0, 1000.0)
        z = random.uniform(-1000.0, 1000.0)

        args = [seq, f"{x:.6f}", f"{y:.6f}", f"{z:.6f}"]

        oracle_cmd = [oracle_bin] + args
        agent_cmd = ["python3", agent_script] + args

        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on input {args}: {oracle_res.stderr}"

        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on input {args}.\nStderr: {agent_res.stderr}"

        oracle_out = oracle_res.stdout.strip()
        agent_out = agent_res.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on iteration {i+1}:\n"
            f"Input: seq={seq}, x={args[1]}, y={args[2]}, z={args[3]}\n"
            f"Expected (Oracle) output: '{oracle_out}'\n"
            f"Actual (Agent) output: '{agent_out}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
