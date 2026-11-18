#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

AGENT_SCRIPT = "/home/user/mc_sim.py"
ORACLE_SCRIPT = "/tests/oracle_sim.py"
NUM_TESTS = 100

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"

def test_fuzz_equivalence():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}."
    assert os.path.exists(ORACLE_SCRIPT), f"Oracle script missing at {ORACLE_SCRIPT}."

    random.seed(12345)

    for i in range(NUM_TESTS):
        seed = random.randint(0, 1000000)
        num_steps = random.randint(10, 5000)

        # Run Oracle
        oracle_cmd = ["python3", ORACLE_SCRIPT, str(seed), str(num_steps)]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on seed={seed}, num_steps={num_steps}. Stderr: {oracle_res.stderr}"
        oracle_out = oracle_res.stdout.strip()

        # Run Agent
        agent_cmd = ["python3", AGENT_SCRIPT, str(seed), str(num_steps)]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on seed={seed}, num_steps={num_steps}. Stderr: {agent_res.stderr}"
        agent_out = agent_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Output mismatch on iteration {i+1}:\n"
            f"Input: seed={seed}, num_steps={num_steps}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Actual (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
