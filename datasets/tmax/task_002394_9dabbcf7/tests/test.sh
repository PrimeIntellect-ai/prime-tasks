#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import sqlite3
import subprocess
import pytest

DB_PATH = "/home/user/data/graph.db"
QUERY = """
SELECT c.name
FROM nodes a
JOIN edges e1 NOT INDEXED ON a.id = e1.src
JOIN nodes b ON e1.dst = b.id
JOIN edges e2 NOT INDEXED ON b.id = e2.src
JOIN nodes c ON e2.dst = c.id
WHERE a.id = ?
  AND a.label = 'User'
  AND e1.rel = 'FOLLOWS'
  AND b.label = 'User'
  AND e2.rel = 'PURCHASED'
  AND c.label = 'Item'
ORDER BY c.name;
"""

def expected_output(start_id):
    with sqlite3.connect(DB_PATH) as conn:
        rows = conn.execute(QUERY, (start_id,)).fetchall()
    return "".join(f"{row[0]}\n" for row in rows)

def test_query_tool_equivalence():
    agent_bin = "/home/user/query_tool"

    assert os.path.isfile(agent_bin), f"Agent executable {agent_bin} not found. Did you compile it?"
    assert os.access(agent_bin, os.X_OK), f"Agent executable {agent_bin} is not executable."

    random.seed(42)
    num_tests = 50
    test_inputs = [str(random.randint(1, 1000)) for _ in range(num_tests)]

    for val in test_inputs:
        oracle_output = expected_output(int(val))

        try:
            agent_res = subprocess.run(
                [agent_bin, val],
                capture_output=True,
                text=True,
                timeout=5
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Your program timed out on input {val}")

        assert agent_res.returncode == 0, (
            f"Your program failed (exit code {agent_res.returncode}) on input {val}. "
            f"Stderr: {agent_res.stderr}"
        )

        if agent_res.stdout != oracle_output:
            pytest.fail(
                f"Output mismatch on input '{val}'.\n"
                f"Expected:\n{oracle_output}\n"
                f"Got (Yours):\n{agent_res.stdout}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
