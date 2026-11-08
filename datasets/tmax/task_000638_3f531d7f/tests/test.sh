#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sqlite3
import subprocess
import json
import random
import tempfile

def test_bom_extractor_fuzz_equivalence():
    oracle_path = "/opt/verifier/reference_bom_extractor"
    agent_path = "/app/bom_extractor/target/release/bom_extractor"

    assert os.path.isfile(oracle_path), f"Oracle not found at {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent binary not found at {agent_path}. Did you run 'cargo build --release'?"

    random.seed(42)

    for i in range(50):
        with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
            db_path = tmp.name

        try:
            conn = sqlite3.connect(db_path)
            cur = conn.cursor()
            cur.execute("CREATE TABLE parts (id INTEGER PRIMARY KEY, name TEXT)")
            cur.execute("CREATE TABLE assemblies (parent_id INTEGER, child_id INTEGER, quantity INTEGER)")

            num_parts = random.randint(5, 20)
            parts = []
            for pid in range(1, num_parts + 1):
                name = f"Part_{pid}_{random.randint(100, 999)}"
                cur.execute("INSERT INTO parts (id, name) VALUES (?, ?)", (pid, name))
                parts.append(pid)

            # Create a DAG to avoid infinite recursion cycles
            for pid in range(1, num_parts + 1):
                num_children = random.randint(0, 3)
                possible_children = [c for c in range(pid + 1, num_parts + 1)]
                if possible_children:
                    children = random.sample(possible_children, min(num_children, len(possible_children)))
                    for child in children:
                        qty = random.randint(1, 5)
                        cur.execute("INSERT INTO assemblies (parent_id, child_id, quantity) VALUES (?, ?, ?)", (pid, child, qty))

            conn.commit()
            conn.close()

            root_part = random.choice(parts)

            oracle_cmd = [oracle_path, db_path, str(root_part)]
            agent_cmd = [agent_path, db_path, str(root_part)]

            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

            assert agent_res.returncode == 0, f"Agent failed with error:\n{agent_res.stderr}\nCommand: {' '.join(agent_cmd)}"
            assert oracle_res.returncode == 0, f"Oracle failed with error:\n{oracle_res.stderr}\nCommand: {' '.join(oracle_cmd)}"

            try:
                oracle_json = json.loads(oracle_res.stdout)
            except json.JSONDecodeError:
                oracle_json = oracle_res.stdout.strip()

            try:
                agent_json = json.loads(agent_res.stdout)
            except json.JSONDecodeError:
                assert False, f"Agent output is not valid JSON:\n{agent_res.stdout}"

            assert agent_json == oracle_json, f"Mismatch on root part {root_part} in generated DB.\nOracle output: {oracle_json}\nAgent output: {agent_json}"

        finally:
            if os.path.exists(db_path):
                os.remove(db_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
