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

def test_fuzz_equivalence():
    agent_script = "/home/user/audit_path_finder.py"
    oracle_bin = "/tests/oracle_audit_path_finder"

    assert os.path.exists(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.exists(oracle_bin), f"Oracle binary not found at {oracle_bin}"
    assert os.access(oracle_bin, os.X_OK), f"Oracle binary is not executable: {oracle_bin}"

    random.seed(42)
    # Generate 200 random inputs matching the regex ^CORP-[0-9]{1,4}$
    fuzz_inputs = [f"CORP-{random.randint(0, 9999)}" for _ in range(200)]

    for target_id in fuzz_inputs:
        # Run the oracle supplied only at verification time
        oracle_cmd = [oracle_bin, target_id]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        oracle_stdout = oracle_res.stdout.strip()

        # Run the agent's script
        agent_cmd = [sys.executable, agent_script, target_id]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        agent_stdout = agent_res.stdout.strip()

        # Assert equivalence
        assert agent_stdout == oracle_stdout, (
            f"Output mismatch for input: '{target_id}'\n"
            f"Expected (Oracle): {oracle_stdout}\n"
            f"Got (Agent): {agent_stdout}\n"
            f"Agent STDERR: {agent_res.stderr.strip()}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
