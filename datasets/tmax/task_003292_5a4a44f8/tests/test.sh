#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

def test_simulate_growth_script_exists():
    """Verify that the agent's script exists and is executable."""
    script_path = "/home/user/simulate_growth.sh"
    assert os.path.isfile(script_path), f"Agent's script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Agent's script at {script_path} is not executable"

def test_fuzz_equivalence():
    """Fuzz test the agent's script against the oracle."""
    script_path = "/home/user/simulate_growth.sh"
    oracle_path = "/tests/oracle_solver"

    assert os.path.isfile(oracle_path), f"Oracle not found at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle at {oracle_path} is not executable"

    random.seed(42)
    num_runs = 100

    for i in range(num_runs):
        p0 = round(random.uniform(10.0, 1000.0), 4)
        dt = round(random.uniform(0.01, 0.5), 4)
        n = random.randint(10, 1000)

        args = [str(p0), str(dt), str(n)]

        oracle_cmd = [oracle_path] + args
        oracle_result = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_result.returncode == 0, f"Oracle failed on input {args} with error: {oracle_result.stderr}"
        oracle_output = oracle_result.stdout.strip()

        agent_cmd = ["/bin/bash", script_path] + args
        agent_result = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_result.returncode == 0, f"Agent script failed on input {args} with error: {agent_result.stderr}"
        agent_output = agent_result.stdout.strip()

        assert agent_output == oracle_output, (
            f"Mismatch on fuzz run {i+1}/{num_runs}.\n"
            f"Inputs (P0, dt, N): {args}\n"
            f"Expected (Oracle): {oracle_output}\n"
            f"Got (Agent): {agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
