#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import string
import subprocess
import pytest

ORACLE_PATH = "/app/sql_generator"
AGENT_PATH = "/home/user/generate_query.py"
N_ITERATIONS = 100

def generate_random_args():
    direction = random.choice(["ANCESTOR", "DESCENDANT"])
    table_len = random.randint(3, 15)
    chars = string.ascii_letters + string.digits + "_"
    table_name = "".join(random.choice(chars) for _ in range(table_len))
    start_id = random.randint(1, 100000)
    return [direction, table_name, str(start_id)]

def test_fuzz_equivalence():
    """Test that the agent's Python script behaves identically to the oracle binary."""
    assert os.path.exists(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"
    assert os.path.exists(AGENT_PATH), f"Agent script missing at {AGENT_PATH}"

    random.seed(42)

    for i in range(N_ITERATIONS):
        args = generate_random_args()

        oracle_cmd = [ORACLE_PATH] + args
        agent_cmd = ["python3", AGENT_PATH] + args

        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

        assert oracle_res.returncode == 0, f"Oracle failed unexpectedly on args {args}"
        assert agent_res.returncode == 0, f"Agent script failed on args {args}. Stderr: {agent_res.stderr}"

        assert agent_res.stdout == oracle_res.stdout, (
            f"Output mismatch on iteration {i+1} with args: {args}\n"
            f"--- Expected (Oracle) ---\n{oracle_res.stdout}\n"
            f"--- Got (Agent) ---\n{agent_res.stdout}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
