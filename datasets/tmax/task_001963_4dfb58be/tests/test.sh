#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import sqlite3
import subprocess


def test_graph_audit_script_exists():
    assert os.path.isfile('/home/user/graph_audit.py'), "/home/user/graph_audit.py does not exist."


def test_fuzz_equivalence():
    agent_script = '/home/user/graph_audit.py'
    oracle_script = '/tests/oracle_audit.py'

    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} missing!"

    random.seed(42)
    test_inputs = [random.randint(1, 1000) for _ in range(100)]

    for account_id in test_inputs:
        # Restore the named index before each agent invocation so the agent script
        # itself must remove it rather than inheriting the oracle's side effect.
        with sqlite3.connect('/app/ledger.db') as conn:
            conn.execute('CREATE INDEX IF NOT EXISTS idx_corrupted_src ON transfers(src)')

        agent_cmd = ['python3', agent_script, str(account_id)]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, (
            f"Agent script failed on input {account_id}:\n{agent_res.stderr}"
        )
        agent_out = agent_res.stdout.strip()

        with sqlite3.connect('/app/ledger.db') as conn:
            remaining = conn.execute(
                "SELECT COUNT(*) FROM sqlite_master "
                "WHERE type = 'index' AND name = 'idx_corrupted_src'"
            ).fetchone()[0]
        assert remaining == 0, "Agent script did not drop idx_corrupted_src"

        oracle_cmd = ['python3', oracle_script, str(account_id)]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, (
            f"Oracle failed on input {account_id}:\n{oracle_res.stderr}"
        )
        oracle_out = oracle_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on account_id={account_id}.\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
