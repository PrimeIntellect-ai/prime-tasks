#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

def test_restore_planner_exists():
    agent_bin = '/home/user/restore_planner'
    assert os.path.isfile(agent_bin), f"Agent binary {agent_bin} is missing."
    assert os.access(agent_bin, os.X_OK), f"Agent binary {agent_bin} is not executable."

def test_fuzz_equivalence():
    agent_bin = '/home/user/restore_planner'
    oracle_bin = '/tests/oracle_planner'

    assert os.path.isfile(oracle_bin), f"Oracle binary {oracle_bin} is missing."
    assert os.access(oracle_bin, os.X_OK), f"Oracle binary {oracle_bin} is not executable."

    random.seed(42)
    databases = ['users', 'inventory', 'billing', 'orders', 'notifications']
    cases = []

    for i in range(100):
        db_name = random.choice(databases)
        timestamp = str(random.randint(1600000000, 1700000000))
        args = [db_name, timestamp]

        try:
            oracle_res = subprocess.run(
                [oracle_bin] + args,
                capture_output=True,
                text=True,
                check=True
            )
            oracle_out = oracle_res.stdout
        except subprocess.CalledProcessError as e:
            oracle_out = e.stdout + e.stderr

        cases.append((db_name, timestamp, oracle_out))

    # The oracle is needed only to generate expected results. Remove it before
    # executing the submitted artifact so the artifact cannot delegate to it.
    os.unlink(oracle_bin)

    for db_name, timestamp, oracle_out in cases:
        args = [db_name, timestamp]

        try:
            agent_res = subprocess.run(
                [agent_bin] + args,
                capture_output=True,
                text=True,
                check=True
            )
            agent_out = agent_res.stdout
        except subprocess.CalledProcessError as e:
            agent_out = e.stdout + e.stderr

        assert agent_out == oracle_out, (
            f"Mismatch on input: db_name='{db_name}', timestamp='{timestamp}'\n"
            f"Oracle output:\n{oracle_out}\n"
            f"Agent output:\n{agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
