#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import random
import subprocess
import pytest

def test_environment_setup():
    """Check if the directory and bashrc modifications are correct."""
    finops_dir = "/home/user/finops"
    assert os.path.isdir(finops_dir), f"Directory {finops_dir} does not exist."

    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"File {bashrc_path} does not exist."

    with open(bashrc_path, "r") as f:
        bashrc_content = f.read()

    assert "FINOPS_LOG_PATH" in bashrc_content and "/home/user/finops/optimizer.log" in bashrc_content, \
        "FINOPS_LOG_PATH environment variable is not set correctly in .bashrc"

def test_fuzz_equivalence_and_logging():
    """Fuzz test the agent's script against the oracle and check logs."""
    oracle_path = "/tests/oracle_optimizer"
    agent_script = "/home/user/finops/optimizer.py"

    assert os.path.isfile(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle at {oracle_path} is not executable"
    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"

    # Generate 1000 random inputs
    random.seed(42)
    inputs = []
    for _ in range(1000):
        gb = random.randint(1, 500000)
        req = random.randint(0, 1000000)
        inputs.append(f"{gb} {req}")

    input_data = "\n".join(inputs) + "\n"

    # Run oracle
    oracle_proc = subprocess.run(
        [oracle_path],
        input=input_data,
        text=True,
        capture_output=True
    )
    assert oracle_proc.returncode == 0, f"Oracle failed with error: {oracle_proc.stderr}"
    oracle_output = oracle_proc.stdout.strip().split("\n")

    # Run agent script
    env = os.environ.copy()
    env["FINOPS_LOG_PATH"] = "/home/user/finops/optimizer.log"

    agent_proc = subprocess.run(
        [sys.executable, agent_script],
        input=input_data,
        text=True,
        capture_output=True,
        env=env
    )
    assert agent_proc.returncode == 0, f"Agent script failed with error: {agent_proc.stderr}"
    agent_output = agent_proc.stdout.strip().split("\n")

    assert len(oracle_output) == len(inputs), "Oracle did not produce the expected number of outputs."
    assert len(agent_output) == len(inputs), "Agent script did not produce the expected number of outputs."

    # Compare outputs
    for i, (oracle_val, agent_val) in enumerate(zip(oracle_output, agent_output)):
        assert oracle_val == agent_val, \
            f"Mismatch on input '{inputs[i]}'. Oracle: {oracle_val}, Agent: {agent_val}"

    # Check logging
    log_path = "/home/user/finops/optimizer.log"
    assert os.path.isfile(log_path), f"Log file missing at {log_path}"

    with open(log_path, "r") as f:
        log_content = f.read()

    # Just check if at least one expected log line is present
    last_input = inputs[-1].split()
    expected_log = f"Processing record: {last_input[0]} GB, {last_input[1]} requests"
    assert expected_log in log_content, f"Expected log message '{expected_log}' not found in log file."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
