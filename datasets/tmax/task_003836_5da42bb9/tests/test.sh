#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_spectral_filter_exists_and_executable():
    """Check if the student's script exists and is executable."""
    script_path = "/home/user/spectral_filter.sh"
    assert os.path.exists(script_path), f"Student script {script_path} is missing."
    assert os.path.isfile(script_path), f"{script_path} is not a regular file."
    assert os.access(script_path, os.X_OK), f"Student script {script_path} is not executable."

def test_fuzz_equivalence():
    """Fuzz test the student's script against the oracle implementation."""
    oracle_path = "/tests/oracle_filter"
    agent_path = "/home/user/spectral_filter.sh"

    assert os.path.exists(oracle_path), f"Oracle script {oracle_path} is missing."
    assert os.access(oracle_path, os.X_OK), f"Oracle script {oracle_path} is not executable."

    random.seed(42)
    num_tests = 200

    for i in range(num_tests):
        length = random.randint(5, 50)
        args = [str(random.randint(-50, 500)) for _ in range(length)]

        # Run oracle
        oracle_cmd = [oracle_path] + args
        oracle_result = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_result.returncode == 0, f"Oracle failed on input: {args}"
        oracle_output = oracle_result.stdout.strip()

        # Run agent
        agent_cmd = [agent_path] + args
        agent_result = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_result.returncode == 0, f"Agent script failed (return code {agent_result.returncode}) on input: {' '.join(args)}\nStderr: {agent_result.stderr}"
        agent_output = agent_result.stdout.strip()

        # Compare
        assert agent_output == oracle_output, (
            f"Output mismatch on test {i+1}/{num_tests}.\n"
            f"Input: {' '.join(args)}\n"
            f"Expected (Oracle): {oracle_output}\n"
            f"Got (Agent):       {agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
