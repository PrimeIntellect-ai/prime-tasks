#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import random
import subprocess
import pytest


def test_database_edges_inserted():
    db_path = "/app/lineage.db"
    assert os.path.exists(db_path), f"Database {db_path} not found."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    expected_edges = [
        (12, 45, 2),
        (45, 8, 5),
        (8, 31, 1)
    ]

    for src, tgt, wt in expected_edges:
        cursor.execute(
            "SELECT COUNT(*) FROM edges WHERE source=? AND target=? AND weight=?",
            (src, tgt, wt),
        )
        count = cursor.fetchone()[0]
        assert count >= 1, (
            f"Expected edge (source={src}, target={tgt}, weight={wt}) "
            "from the audio transcription was not found in the edges table."
        )

    conn.close()


def test_fuzz_equivalence():
    agent_bin = "/home/user/path_finder"
    oracle_bin = "/tests/oracle_path_finder"

    assert os.path.exists(agent_bin), f"Agent binary {agent_bin} not found. Did you compile it?"
    assert os.access(agent_bin, os.X_OK), f"Agent binary {agent_bin} is not executable."

    assert os.path.exists(oracle_bin), f"Oracle binary {oracle_bin} not found."
    assert os.access(oracle_bin, os.X_OK), f"Oracle binary {oracle_bin} is not executable."

    random.seed(42)
    pairs = [(random.randint(1, 50), random.randint(1, 50)) for _ in range(500)]
    expected = []

    for u, v in pairs:
        try:
            oracle_res = subprocess.run(
                [oracle_bin, str(u), str(v)],
                capture_output=True,
                text=True,
                timeout=5,
            )
        except subprocess.TimeoutExpired as e:
            pytest.fail(f"Timeout while running oracle on input ({u}, {v}). Command: {e.cmd}.")
        expected.append(oracle_res.stdout.strip())

    # The oracle is supplied only for verification. Remove it before executing
    # the submission so a wrapper cannot delegate its work to the oracle.
    os.unlink(oracle_bin)

    for (u, v), oracle_out in zip(pairs, expected):
        agent_cmd = [agent_bin, str(u), str(v)]
        try:
            agent_res = subprocess.run(
                agent_cmd,
                capture_output=True,
                text=True,
                timeout=5,
            )
        except subprocess.TimeoutExpired as e:
            pytest.fail(
                f"Timeout while running binary on input ({u}, {v}). Command: {e.cmd}. "
                "You might have an infinite loop."
            )

        agent_out = agent_res.stdout.strip()
        assert agent_out == oracle_out, (
            f"Output mismatch on input ({u}, {v}).\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
