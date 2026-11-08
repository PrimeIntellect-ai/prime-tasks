#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

ORACLE_PATH = "/tests/oracle_evaluator"
AGENT_PATH = "/home/user/evaluator"
N_ITERATIONS = 100

def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable is not executable: {AGENT_PATH}"

    assert os.path.isfile(ORACLE_PATH), f"Oracle executable not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle executable is not executable: {ORACLE_PATH}"

    random.seed(42)

    for _ in range(N_ITERATIONS):
        x = random.randint(-1000, 1000)
        y = random.randint(-1000, 1000)
        z = random.randint(-1000, 1000)

        args = [str(x), str(y), str(z)]

        oracle_cmd = [ORACLE_PATH] + args
        agent_cmd = [AGENT_PATH] + args

        oracle_proc = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_proc.returncode == 0, f"Oracle failed on input {args}"
        oracle_out = oracle_proc.stdout

        agent_proc = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_proc.returncode == 0, f"Agent program failed (return code {agent_proc.returncode}) on input {args}. stderr: {agent_proc.stderr}"
        agent_out = agent_proc.stdout

        assert agent_out == oracle_out, (
            f"Mismatch on input X={x}, Y={y}, Z={z}.\n"
            f"Oracle output: {repr(oracle_out)}\n"
            f"Agent output: {repr(agent_out)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
