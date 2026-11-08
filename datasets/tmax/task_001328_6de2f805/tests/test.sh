#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

def test_query_path_exists():
    assert os.path.isfile("/home/user/query_path.py"), "Agent script /home/user/query_path.py is missing."

def test_fuzz_equivalence():
    agent_script = "/home/user/query_path.py"
    oracle_script = "/tests/oracle_path.py"

    assert os.path.isfile(agent_script), f"Missing {agent_script}"
    assert os.path.isfile(oracle_script), f"Missing {oracle_script}"

    random.seed(42)
    N = 100
    pairs = [(random.randint(1, 100), random.randint(1, 100)) for _ in range(N)]

    for u, v in pairs:
        # Run oracle
        oracle_cmd = ["python3", oracle_script, str(u), str(v)]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on input {u} {v}: {oracle_res.stderr}"
        oracle_out = oracle_res.stdout.strip()

        # Run agent
        agent_cmd = ["python3", agent_script, str(u), str(v)]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

        assert agent_res.returncode == 0, f"Agent script failed on input {u} {v}. stderr: {agent_res.stderr}"
        agent_out = agent_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on input {u} {v}.\n"
            f"Oracle output: '{oracle_out}'\n"
            f"Agent output: '{agent_out}'"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
