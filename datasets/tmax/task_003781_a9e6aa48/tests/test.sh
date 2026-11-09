#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sqlite3
import random
import subprocess
import tempfile
import pytest

AGENT_SCRIPT = "/home/user/graph_builder.py"
ORACLE_SCRIPT = "/tests/oracle.py"

def generate_fuzz_db(db_path, seed):
    rng = random.Random(seed)
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("CREATE TABLE researchers (id INTEGER PRIMARY KEY)")
    cur.execute("CREATE TABLE documents (id INTEGER PRIMARY KEY, year INTEGER)")
    cur.execute("CREATE TABLE wrote (researcher_id INTEGER, document_id INTEGER)")

    num_researchers = rng.randint(50, 200)
    num_documents = rng.randint(100, 500)
    num_wrote = rng.randint(300, 1000)

    researchers = [(i,) for i in range(1, num_researchers + 1)]
    cur.executemany("INSERT INTO researchers (id) VALUES (?)", researchers)

    documents = [(i, rng.randint(2000, 2023)) for i in range(1, num_documents + 1)]
    cur.executemany("INSERT INTO documents (id, year) VALUES (?, ?)", documents)

    wrote = [(rng.randint(1, num_researchers), rng.randint(1, num_documents)) for _ in range(num_wrote)]
    cur.executemany("INSERT INTO wrote (researcher_id, document_id) VALUES (?, ?)", wrote)

    conn.commit()
    conn.close()

    return rng.choice(researchers)[0]

def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script not found at {ORACLE_SCRIPT}"

    N = 25
    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(N):
            db_path = os.path.join(tmpdir, f"fuzz_{i}.db")
            researcher_id = generate_fuzz_db(db_path, seed=42 + i)

            # Run oracle
            oracle_cmd = ["python3", ORACLE_SCRIPT, "--db-path", db_path, "--researcher-id", str(researcher_id)]
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True, check=True)
            oracle_output = oracle_res.stdout.strip()

            # Run agent
            agent_cmd = ["python3", AGENT_SCRIPT, "--db-path", db_path, "--researcher-id", str(researcher_id)]
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

            assert agent_res.returncode == 0, f"Agent script failed on fuzz iteration {i}. Error:\n{agent_res.stderr}"
            agent_output = agent_res.stdout.strip()

            assert agent_output == oracle_output, (
                f"Mismatch on fuzz iteration {i}.\n"
                f"Researcher ID: {researcher_id}\n"
                f"Oracle Output: {oracle_output}\n"
                f"Agent Output: {agent_output}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
