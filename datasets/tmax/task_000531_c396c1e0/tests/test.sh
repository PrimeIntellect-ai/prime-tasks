#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

def test_evaluator_script_exists():
    assert os.path.isfile("/home/user/evaluator.py"), "/home/user/evaluator.py is missing"

def test_shared_library_built():
    assert os.path.isfile("/app/c_src/libtransform.so"), "/app/c_src/libtransform.so is missing"

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_evaluator"
    agent_script = "/home/user/evaluator.py"

    assert os.path.isfile(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle at {oracle_path} is not executable"

    random.seed(42)
    inputs = [random.randint(0, 50000) for _ in range(200)]

    for x in inputs:
        oracle_cmd = [oracle_path, str(x)]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on input {x}: {oracle_res.stderr}"
        oracle_output = oracle_res.stdout.strip()

        agent_cmd = ["python3", agent_script, str(x)]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on input {x}: {agent_res.stderr}"
        agent_output = agent_res.stdout.strip()

        assert agent_output == oracle_output, f"Mismatch on input {x}. Oracle: '{oracle_output}', Agent: '{agent_output}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
