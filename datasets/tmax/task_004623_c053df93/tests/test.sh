#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_audit_query_exists():
    script_path = "/home/user/audit_query.py"
    assert os.path.exists(script_path), f"Agent's script missing at {script_path}"
    assert os.path.isfile(script_path), f"{script_path} is not a file"

def test_fuzz_equivalence():
    agent_script = "/home/user/audit_query.py"
    oracle_script = "/tests/oracle_audit_query.py"

    assert os.path.exists(agent_script), f"Agent's script missing at {agent_script}"
    assert os.path.exists(oracle_script), f"Oracle script missing at {oracle_script}"

    random.seed(42)
    N = 100
    badge_ids = [101, 102, 103, 104, 105]

    for i in range(N):
        badge_id = random.choice(badge_ids)
        start_time = random.randint(0, 3600)
        end_time = start_time + random.randint(10, 600)

        args = [str(badge_id), str(start_time), str(end_time)]

        oracle_cmd = ["python3", oracle_script] + args
        agent_cmd = ["python3", agent_script] + args

        try:
            oracle_result = subprocess.run(oracle_cmd, capture_output=True, text=True, check=True, timeout=5)
            oracle_output = oracle_result.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle script failed on input {args}. Error: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle script timed out on input {args}.")

        try:
            agent_result = subprocess.run(agent_cmd, capture_output=True, text=True, check=True, timeout=5)
            agent_output = agent_result.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on input {args}. Error: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input {args}.")

        assert agent_output == oracle_output, (
            f"Mismatch on input badge_id={badge_id}, start_time={start_time}, end_time={end_time}.\n"
            f"Oracle output: {oracle_output}\n"
            f"Agent output: {agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
