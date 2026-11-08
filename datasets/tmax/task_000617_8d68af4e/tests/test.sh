#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

AGENT_SCRIPT = "/home/user/extract_embeddings.py"
ORACLE_SCRIPT = "/tests/oracle_extract_embeddings.py"

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_SCRIPT), f"Oracle script missing at {ORACLE_SCRIPT}"

    random.seed(42)
    # Generate random frame indices between 0 and 100, plus some out-of-bounds edge cases
    test_inputs = [random.randint(0, 100) for _ in range(20)]
    test_inputs.extend([-10, 500, 9999])

    for val in test_inputs:
        # Run oracle
        oracle_cmd = ["python3", ORACLE_SCRIPT, str(val)]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        oracle_out = oracle_res.stdout.strip()

        # Run agent
        agent_cmd = ["python3", AGENT_SCRIPT, str(val)]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        agent_out = agent_res.stdout.strip()

        # Check for matching outputs
        error_msg = (
            f"Mismatch on input '{val}'.\n"
            f"Expected output:\n{oracle_out}\n"
            f"Agent output:\n{agent_out}\n"
            f"Agent stderr:\n{agent_res.stderr}"
        )
        assert agent_out == oracle_out, error_msg
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
