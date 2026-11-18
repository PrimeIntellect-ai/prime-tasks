#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import json
import sqlite3
import tempfile
import shutil
import pwd


def test_network_db_exists():
    db_path = "/home/user/network.db"
    assert os.path.exists(db_path), f"Database file {db_path} does not exist."
    assert os.path.isfile(db_path), f"{db_path} is not a file."

    # Check if 'edges' table exists and has correct columns
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='edges'")
    assert cur.fetchone() is not None, "Table 'edges' does not exist in the database."

    cur.execute("PRAGMA table_info(edges)")
    columns = {row[1] for row in cur.fetchall()}
    assert {"source", "target", "bytes"}.issubset(columns), f"Table 'edges' is missing required columns. Found: {columns}"
    conn.close()


def test_script_is_executable():
    script_path = "/home/user/query_network.py"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def _demote_to_user():
    account = pwd.getpwnam("user")
    os.setgroups([])
    os.setgid(account.pw_gid)
    os.setuid(account.pw_uid)


def test_fuzz_equivalence():
    agent_script = "/home/user/query_network.py"
    shipped_oracle_script = "/tests/oracle_query_network.py"
    shipped_oracle_db = "/tests/network.db"

    assert os.path.exists(agent_script), f"Agent script {agent_script} is missing."
    assert os.path.isfile(shipped_oracle_script), "Verifier oracle script is missing."
    assert os.path.isfile(shipped_oracle_db), "Verifier oracle database is missing."

    # Keep verification-only oracle data inaccessible to the submitted program.
    os.chown(shipped_oracle_script, 0, 0)
    os.chown(shipped_oracle_db, 0, 0)
    os.chmod(shipped_oracle_script, 0o600)
    os.chmod(shipped_oracle_db, 0o600)

    private_dir = tempfile.mkdtemp(prefix="network_oracle_", dir="/tmp")
    os.chmod(private_dir, 0o700)
    private_db = os.path.join(private_dir, "network.db")
    private_script = os.path.join(private_dir, "oracle_query_network.py")
    shutil.copyfile(shipped_oracle_db, private_db)
    with open(shipped_oracle_script, "r", encoding="utf-8") as src:
        oracle_source = src.read()
    oracle_source = oracle_source.replace("/opt/oracle/network.db", private_db)
    with open(private_script, "w", encoding="utf-8") as dst:
        dst.write(oracle_source)
    os.chmod(private_db, 0o600)
    os.chmod(private_script, 0o700)

    choices = ["Alpha_1", "Beta_2", "Gamma_3", "Delta_2", "Xray_9", "Zulu_0", "Echo_5"]
    random.seed(42)
    inputs = [random.choice(choices) for _ in range(20)]

    try:
        for node_id in inputs:
            # Run the submission as the unprivileged task user so it cannot read
            # verification-only oracle files.
            agent_cmd = ["/usr/bin/python3", agent_script, node_id]
            agent_res = subprocess.run(
                agent_cmd,
                capture_output=True,
                text=True,
                preexec_fn=_demote_to_user,
            )
            assert agent_res.returncode == 0, f"Agent script failed on input {node_id}. Error:\n{agent_res.stderr}"

            # Run the verification-only oracle as root.
            oracle_cmd = ["/usr/bin/python3", private_script, node_id]
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
            assert oracle_res.returncode == 0, f"Oracle script failed on input {node_id}. Error:\n{oracle_res.stderr}"

            # Parse JSON
            try:
                agent_json = json.loads(agent_res.stdout)
            except json.JSONDecodeError:
                assert False, f"Agent output is not valid JSON on input {node_id}. Output:\n{agent_res.stdout}"

            try:
                oracle_json = json.loads(oracle_res.stdout)
            except json.JSONDecodeError:
                assert False, f"Oracle output is not valid JSON on input {node_id}. Output:\n{oracle_res.stdout}"

            assert agent_json == oracle_json, (
                f"Mismatch on input {node_id}.\n"
                f"Expected: {oracle_json}\n"
                f"Got: {agent_json}"
            )
    finally:
        shutil.rmtree(private_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
