#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import random
import subprocess
import pytest

ORACLE_PATH = "/tests/oracle_estimate"
AGENT_PATH = "/home/user/migrate_and_estimate.py"
N_ITERATIONS = 100

def generate_random_input():
    modules = [{"id": i, "size": random.randint(0, 1000)} for i in range(30)]
    return json.dumps({"schema_version": 1, "modules": modules})

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.path.exists(AGENT_PATH), f"Agent script missing at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script is not executable: {AGENT_PATH}"

    random.seed(42)

    for i in range(N_ITERATIONS):
        input_json = generate_random_input()

        oracle_proc = subprocess.run(
            [ORACLE_PATH, input_json],
            capture_output=True,
            text=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input: {input_json}\nStderr: {oracle_proc.stderr}"
        oracle_out = oracle_proc.stdout.strip()

        agent_proc = subprocess.run(
            [AGENT_PATH, input_json],
            capture_output=True,
            text=True
        )
        assert agent_proc.returncode == 0, f"Agent script failed on input: {input_json}\nStderr: {agent_proc.stderr}"
        agent_out = agent_proc.stdout.strip()

        assert agent_out == oracle_out, (
            f"Output mismatch on iteration {i}!\n"
            f"Input: {input_json}\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output:  {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
