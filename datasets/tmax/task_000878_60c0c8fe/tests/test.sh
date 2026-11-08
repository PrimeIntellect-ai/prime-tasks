#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

def test_agent_executable_exists():
    agent_path = "/home/user/mesh_solver"
    assert os.path.exists(agent_path), f"Agent executable {agent_path} is missing."
    assert os.path.isfile(agent_path), f"{agent_path} is not a file."
    assert os.access(agent_path, os.X_OK), f"Agent executable {agent_path} is not executable."

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_solver"
    agent_path = "/home/user/mesh_solver"

    assert os.path.exists(oracle_path), f"Oracle {oracle_path} missing."
    assert os.path.exists(agent_path), f"Agent {agent_path} missing."

    random.seed(42)
    num_tests = 1000

    for _ in range(num_tests):
        cx = random.uniform(-2.0, 2.0)
        cy = random.uniform(-2.0, 2.0)
        R = random.uniform(0.5, 5.0)

        args = [f"{cx:.6f}", f"{cy:.6f}", f"{R:.6f}"]

        oracle_cmd = [oracle_path] + args
        agent_cmd = [agent_path] + args

        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on inputs {args}"
        oracle_out = oracle_res.stdout.strip()

        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent failed on inputs {args}. stderr: {agent_res.stderr}"
        agent_out = agent_res.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on inputs cx={args[0]}, cy={args[1]}, R={args[2]}.\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output:  {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
