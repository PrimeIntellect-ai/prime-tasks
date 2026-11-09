#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_agent_script_exists_and_executable():
    """Test that the agent script exists and is executable."""
    agent_path = "/home/user/calc_pi.sh"
    assert os.path.exists(agent_path), f"The agent script {agent_path} does not exist."
    assert os.path.isfile(agent_path), f"The path {agent_path} is not a file."
    assert os.access(agent_path, os.X_OK), f"The agent script {agent_path} is not executable."

def test_fuzz_equivalence():
    """Test that the agent script behaves exactly like the oracle script on random inputs."""
    oracle_path = "/tests/oracle_calc_pi.sh"
    agent_path = "/home/user/calc_pi.sh"

    assert os.path.exists(oracle_path), f"Oracle script missing at {oracle_path}"
    assert os.path.exists(agent_path), f"Agent script missing at {agent_path}"

    random.seed(42)
    num_iterations = 200

    for i in range(num_iterations):
        t_seq = random.randint(1000, 100000)
        t_par = random.randint(10, 1000)
        n = random.randint(2, 256)
        c_penalty = random.randint(0, 100)

        args = [str(t_seq), str(t_par), str(n), str(c_penalty)]

        # Run oracle uploaded only at verification time.
        oracle_cmd = ["/bin/bash", oracle_path] + args
        oracle_result = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_result.returncode == 0, f"Oracle failed on input {args}: {oracle_result.stderr}"
        oracle_output = oracle_result.stdout.strip()

        # Run agent
        agent_cmd = [agent_path] + args
        agent_result = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_result.returncode == 0, f"Agent script failed on input {args}. Error: {agent_result.stderr}"
        agent_output = agent_result.stdout.strip()

        assert agent_output == oracle_output, (
            f"Output mismatch on iteration {i+1}.\n"
            f"Input arguments (T_seq, T_par, N, C_penalty): {args}\n"
            f"Expected (Oracle): {oracle_output}\n"
            f"Got (Agent): {agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
