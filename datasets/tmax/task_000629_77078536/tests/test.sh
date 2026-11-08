#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import pytest

def test_fuzz_equivalence():
    """
    Fuzz-equivalence test: compares the agent's script against the oracle
    on N=50 random transaction IDs between 1 and 20.
    """
    agent_script = "/home/user/detect_deadlock.py"
    oracle_script = "/tests/oracle_deadlock.py"

    assert os.path.isfile(agent_script), f"Agent script is missing at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script is missing at {oracle_script}"

    random.seed(42)
    test_inputs = [random.randint(1, 20) for _ in range(50)]

    for tx_id in test_inputs:
        agent_cmd = ["python3", agent_script, str(tx_id)]
        oracle_cmd = ["python3", oracle_script, str(tx_id)]

        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)

        assert agent_res.returncode == 0, (
            f"Agent script crashed on input {tx_id}.\n"
            f"STDERR:\n{agent_res.stderr}"
        )
        assert oracle_res.returncode == 0, (
            f"Oracle script crashed on input {tx_id}.\n"
            f"STDERR:\n{oracle_res.stderr}"
        )

        agent_out = agent_res.stdout.strip()
        oracle_out = oracle_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Output mismatch for Transaction ID {tx_id}.\n"
            f"Expected (Oracle):\n{oracle_out}\n\n"
            f"Got (Agent):\n{agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
