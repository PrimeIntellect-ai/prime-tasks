#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

AGENT_SCRIPT = "/home/user/simulate.sh"
ORACLE_SCRIPT = "/tests/oracle"

def test_agent_script_exists_and_executable():
    """Ensure the agent's script exists and is executable."""
    assert os.path.isfile(AGENT_SCRIPT), f"The script {AGENT_SCRIPT} does not exist."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"The script {AGENT_SCRIPT} is not executable."

def test_fuzz_equivalence():
    """Fuzz test the agent's script against the oracle."""
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script {ORACLE_SCRIPT} is missing."
    assert os.access(ORACLE_SCRIPT, os.X_OK), f"Oracle script {ORACLE_SCRIPT} is not executable."

    random.seed(42)
    num_tests = 50

    for _ in range(num_tests):
        N = random.randint(10, 1000)
        seed = random.randint(0, 99999)

        oracle_cmd = [ORACLE_SCRIPT, str(N), str(seed)]
        oracle_result = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_result.returncode == 0, f"Oracle failed on input N={N}, seed={seed}"
        oracle_output = oracle_result.stdout

        agent_cmd = [AGENT_SCRIPT, str(N), str(seed)]
        agent_result = subprocess.run(agent_cmd, capture_output=True, text=True)

        assert agent_result.returncode == 0, (
            f"Agent script failed on input N={N}, seed={seed}.\n"
            f"Stderr: {agent_result.stderr}"
        )
        agent_output = agent_result.stdout

        assert agent_output == oracle_output, (
            f"Output mismatch on input N={N}, seed={seed}.\n"
            f"Expected (Oracle):\n{oracle_output[:200]}...\n"
            f"Got (Agent):\n{agent_output[:200]}..."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
