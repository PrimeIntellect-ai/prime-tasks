#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/api_v3.py"
ORACLE_PY = "/tests/oracle_py.py"

def test_api_v3_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} is missing."

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PY), f"Oracle {ORACLE_PY} is missing."

    random.seed(42)
    inputs = [random.randint(0, 300) for _ in range(20)]

    for frame_num in inputs:
        input_str = str(frame_num)

        # Run oracle
        oracle_cmd = ["python3", ORACLE_PY, input_str]
        oracle_proc = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_proc.returncode == 0, f"Oracle failed on input {input_str}:\n{oracle_proc.stderr}"
        oracle_output = oracle_proc.stdout.strip()

        # Run agent
        agent_cmd = ["python3", AGENT_SCRIPT, input_str]
        agent_proc = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_proc.returncode == 0, f"Agent script failed on input {input_str}:\n{agent_proc.stderr}"
        agent_output = agent_proc.stdout.strip()

        assert agent_output == oracle_output, (
            f"Mismatch on frame {input_str}.\n"
            f"Oracle output: {oracle_output}\n"
            f"Agent output: {agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
