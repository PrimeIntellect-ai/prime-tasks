#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import subprocess
import random
import string
import tempfile
import pytest

AGENT_SCRIPT = "/home/user/reconcile.py"
ORACLE_SCRIPT = "/tests/oracle_reconcile.py"
NUM_TESTS = 50

def generate_random_string(length=10):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def create_random_db(db_path, seed):
    random.seed(seed)
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute('''CREATE TABLE storage_nodes (
        node_id INTEGER PRIMARY KEY,
        node_name TEXT,
        region TEXT
    )''')
    cur.execute('''CREATE TABLE backup_jobs (
        job_id INTEGER PRIMARY KEY,
        node_id INTEGER,
        status TEXT,
        integrity_hash TEXT,
        completed_at INTEGER
    )''')
    cur.execute('''CREATE TABLE job_chunks (
        chunk_id INTEGER PRIMARY KEY,
        job_id INTEGER,
        bytes_size INTEGER
    )''')

    regions = ['us-east-legacy', 'us-west-1', 'eu-central-1', 'ap-south-1']
    statuses = ['COMPLETED', 'FAILED', 'IN_PROGRESS', 'PENDING']

    num_nodes = random.randint(10, 50)
    for node_id in range(1, num_nodes + 1):
        node_name = f"node_{generate_random_string(5)}"
        region = random.choice(regions)
        cur.execute("INSERT INTO storage_nodes VALUES (?, ?, ?)", (node_id, node_name, region))

        num_jobs = random.randint(0, 100)
        for _ in range(num_jobs):
            status = random.choice(statuses)
            integrity_hash = generate_random_string(16) if random.random() > 0.2 else None
            completed_at = random.randint(1600000000, 1700000000)
            cur.execute("INSERT INTO backup_jobs (node_id, status, integrity_hash, completed_at) VALUES (?, ?, ?, ?)",
                        (node_id, status, integrity_hash, completed_at))
            job_id = cur.lastrowid

            num_chunks = random.randint(1, 20)
            for _ in range(num_chunks):
                bytes_size = random.randint(1000, 10000000)
                cur.execute("INSERT INTO job_chunks (job_id, bytes_size) VALUES (?, ?)", (job_id, bytes_size))

    conn.commit()
    conn.close()

def run_script(script_path, db_path):
    cmd = ["python3", script_path, db_path]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout, result.stderr, result.returncode

def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"

@pytest.mark.parametrize("seed", range(NUM_TESTS))
def test_fuzz_equivalence(seed):
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing: {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script missing: {ORACLE_SCRIPT}"

    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
        db_path = tmp.name

    try:
        create_random_db(db_path, seed)

        oracle_out, oracle_err, oracle_rc = run_script(ORACLE_SCRIPT, db_path)
        agent_out, agent_err, agent_rc = run_script(AGENT_SCRIPT, db_path)

        assert agent_rc == 0, f"Agent script failed with return code {agent_rc}.\nStderr:\n{agent_err}"

        # Compare outputs, ignoring trailing whitespace
        oracle_lines = [line.strip() for line in oracle_out.strip().split('\n') if line.strip()]
        agent_lines = [line.strip() for line in agent_out.strip().split('\n') if line.strip()]

        assert agent_lines == oracle_lines, (
            f"Output mismatch on random DB (seed={seed}).\n"
            f"Expected (oracle):\n{oracle_out}\n"
            f"Got (agent):\n{agent_out}"
        )
    finally:
        if os.path.exists(db_path):
            os.remove(db_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
