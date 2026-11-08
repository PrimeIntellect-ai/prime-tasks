#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_executable_exists():
    agent_executable = "/home/user/etl_query"
    assert os.path.isfile(agent_executable), f"Agent executable {agent_executable} is missing."
    assert os.access(agent_executable, os.X_OK), f"Agent program {agent_executable} is not executable."

def test_fuzz_equivalence():
    agent_executable = "/home/user/etl_query"
    oracle_executable = "/tests/oracle_runner"

    assert os.path.isfile(oracle_executable), f"Oracle executable {oracle_executable} is missing."
    assert os.access(oracle_executable, os.X_OK), f"Oracle program {oracle_executable} is not executable."

    random.seed(42)
    num_iterations = 50

    for i in range(num_iterations):
        u_id = random.randint(1, 20)
        limit = random.randint(1, 15)
        offset = random.randint(0, 10)

        args = [str(u_id), str(limit), str(offset)]

        oracle_cmd = [oracle_executable] + args
        agent_cmd = [agent_executable] + args

        try:
            oracle_result = subprocess.run(oracle_cmd, capture_output=True, text=True, check=True)
            oracle_output = oracle_result.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input {args} with error: {e.stderr}")

        try:
            agent_result = subprocess.run(agent_cmd, capture_output=True, text=True, check=True)
            agent_output = agent_result.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent program failed on input {args} with error: {e.stderr}")

        assert agent_output == oracle_output, (
            f"Output mismatch on iteration {i+1}.\n"
            f"Input args (u_id, limit, offset): {args}\n"
            f"Oracle output:\n{oracle_output}\n"
            f"Agent output:\n{agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
