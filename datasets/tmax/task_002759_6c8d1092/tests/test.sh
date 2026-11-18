#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import json
import random
import sqlite3
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/fetch_data.py"
ORACLE_SCRIPT = "/tests/oracle_fetch.py"
DB_PATH = "/home/user/research_data.db"

def get_researchers():
    """Fetch all researcher names from the database."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM researchers")
    researchers = [row[0] for row in cursor.fetchall()]
    conn.close()
    return researchers

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"Path {AGENT_SCRIPT} is not a file"

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_SCRIPT), f"Oracle script missing at {ORACLE_SCRIPT}"

    researchers = get_researchers()
    assert len(researchers) > 0, "No researchers found in the database"

    random.seed(42)

    for i in range(50):
        researcher = random.choice(researchers)
        min_val = round(random.uniform(0.0, 100.0), 2)

        args = ["--researcher", researcher, "--min-val", str(min_val)]

        # Run oracle
        oracle_cmd = [sys.executable, ORACLE_SCRIPT] + args
        oracle_proc = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i} with args {args}:\n{oracle_proc.stderr}"

        try:
            oracle_output = json.loads(oracle_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Oracle returned invalid JSON on iteration {i} with args {args}:\n{oracle_proc.stdout}")

        # Run agent
        agent_cmd = [sys.executable, AGENT_SCRIPT] + args
        agent_proc = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_proc.returncode == 0, f"Agent script failed on iteration {i} with args {args}:\n{agent_proc.stderr}"

        try:
            agent_output = json.loads(agent_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Agent script returned invalid JSON on iteration {i} with args {args}:\n{agent_proc.stdout}")

        assert agent_output == oracle_output, (
            f"Mismatch on iteration {i} with args {args}.\n"
            f"Expected: {oracle_output}\n"
            f"Got: {agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
