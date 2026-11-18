#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/process_node.sh"
ORACLE_SCRIPT = "/tests/oracle.sh"
NUM_TESTS = 25
MIN_NODE = 1
MAX_NODE = 300

def test_agent_script_exists():
    """Verify that the agent's script exists."""
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."

def test_fuzz_equivalence():
    """Test the agent's script against the oracle script with random inputs."""
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script {ORACLE_SCRIPT} is missing."
    assert os.access(ORACLE_SCRIPT, os.X_OK), f"Oracle script {ORACLE_SCRIPT} is not executable."

    random.seed(1337)
    test_inputs = [random.randint(MIN_NODE, MAX_NODE) for _ in range(NUM_TESTS)]

    for node_id in test_inputs:
        # Run oracle
        oracle_cmd = [ORACLE_SCRIPT, str(node_id)]
        oracle_proc = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_proc.returncode == 0, f"Oracle failed on input {node_id}:\n{oracle_proc.stderr}"
        oracle_output = oracle_proc.stdout.strip()

        # Run agent
        agent_cmd = ["/bin/bash", AGENT_SCRIPT, str(node_id)]
        agent_proc = subprocess.run(agent_cmd, capture_output=True, text=True)

        # We don't strictly assert agent return code unless it's a failure, but output must match
        agent_output = agent_proc.stdout.strip()

        if oracle_output != agent_output:
            error_msg = (
                f"Mismatch on NODE_ID={node_id}\n"
                f"Oracle output: '{oracle_output}'\n"
                f"Agent output:  '{agent_output}'\n"
                f"Agent stderr:  '{agent_proc.stderr.strip()}'"
            )
            pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
