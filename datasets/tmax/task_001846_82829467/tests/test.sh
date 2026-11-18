#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/query_graph.py"
ORACLE_BINARY = "/tests/oracle_query_graph"

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"

def test_oracle_binary_exists():
    assert os.path.exists(ORACLE_BINARY), f"Oracle binary not found at {ORACLE_BINARY}"
    assert os.path.isfile(ORACLE_BINARY), f"{ORACLE_BINARY} is not a file"

def run_command(cmd):
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=5
        )
        return result.stdout, result.stderr, result.returncode
    except subprocess.TimeoutExpired:
        return "", "Timeout", -1

def test_fuzz_equivalence():
    """
    Run the agent script and oracle on 100 random inputs and ensure outputs match exactly.
    """
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing: {AGENT_SCRIPT}"
    assert os.path.exists(ORACLE_BINARY), f"Oracle missing: {ORACLE_BINARY}"

    random.seed(42)
    nodes = ['TX_A', 'TX_B', 'TX_C', 'TX_D', 'TX_E']

    for i in range(100):
        node_id = random.choice(nodes)
        limit = random.randint(1, 10)
        offset = random.randint(0, 10)

        agent_cmd = ["python3", AGENT_SCRIPT, node_id, str(limit), str(offset)]
        oracle_cmd = [ORACLE_BINARY, node_id, str(limit), str(offset)]

        agent_out, agent_err, agent_rc = run_command(agent_cmd)
        oracle_out, oracle_err, oracle_rc = run_command(oracle_cmd)

        error_msg = (
            f"Mismatch on iteration {i+1} with inputs: node_id={node_id}, limit={limit}, offset={offset}\n"
            f"Oracle output:\n{oracle_out}\n"
            f"Agent output:\n{agent_out}\n"
            f"Oracle return code: {oracle_rc}, Agent return code: {agent_rc}\n"
            f"Agent stderr: {agent_err}"
        )

        assert agent_out == oracle_out, error_msg
        assert agent_rc == oracle_rc, error_msg
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
