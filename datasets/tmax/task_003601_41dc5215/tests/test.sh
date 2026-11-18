#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import subprocess
import random
import uuid
import pytest

DB_PATH = "/home/user/backup_topology.db"
AGENT_SCRIPT = "/home/user/impact_analysis.sh"
ORACLE_SCRIPT = "/tests/oracle_impact_analysis.sh"
REPORT_PATH = "/home/user/incident_report.txt"

def run_oracle(node):
    return subprocess.run(["/bin/bash", ORACLE_SCRIPT, node], capture_output=True, text=True)

def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing: {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script not executable: {AGENT_SCRIPT}"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_SCRIPT), "Oracle script missing"
    assert os.path.isfile(DB_PATH), "Database missing"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT DISTINCT source_node FROM backup_dependencies;")
    nodes = [row[0] for row in cursor.fetchall()]
    conn.close()

    assert len(nodes) > 0, "No nodes found in the database to fuzz."

    random.seed(42)
    fuzz_nodes = random.choices(nodes, k=50)

    for node in fuzz_nodes:
        oracle_proc = run_oracle(node)
        agent_proc = subprocess.run([AGENT_SCRIPT, node], capture_output=True, text=True)

        assert oracle_proc.returncode == 0, f"Oracle failed on node {node}:\n{oracle_proc.stderr}"
        assert agent_proc.returncode == 0, f"Agent script failed on node {node}:\n{agent_proc.stderr}"

        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()

        assert agent_out == oracle_out, (
            f"Output mismatch for node '{node}'.\n"
            f"Expected:\n{oracle_out}\n\n"
            f"Got:\n{agent_out}"
        )

def test_generated_graph_inputs():
    prefix = "verifier-" + uuid.uuid4().hex
    root = prefix + "-root"
    left = prefix + "-left"
    right = prefix + "-right"
    shared = prefix + "-shared"
    leaf = prefix + "-leaf"
    isolated = prefix + "-isolated"
    edges = [
        (root, left),
        (root, right),
        (left, shared),
        (right, shared),
        (shared, leaf),
        (leaf, left),
    ]

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executemany(
            "INSERT INTO backup_dependencies (source_node, target_node) VALUES (?, ?)",
            edges,
        )
        conn.commit()

        def expected(start):
            seen = {start}
            pending = [start]
            while pending:
                current = pending.pop()
                rows = conn.execute(
                    "SELECT target_node FROM backup_dependencies WHERE source_node = ?",
                    (current,),
                ).fetchall()
                for (target,) in rows:
                    if target not in seen:
                        seen.add(target)
                        pending.append(target)
            return "\n".join(sorted(seen))

        for node in (root, right, shared, leaf, isolated):
            proc = subprocess.run([AGENT_SCRIPT, node], capture_output=True, text=True)
            assert proc.returncode == 0, f"Agent script failed on generated node {node}:\n{proc.stderr}"
            assert proc.stdout.strip() == expected(node), (
                f"Output mismatch for generated node '{node}'.\n"
                f"Expected:\n{expected(node)}\n\nGot:\n{proc.stdout.strip()}"
            )
    finally:
        conn.execute(
            "DELETE FROM backup_dependencies WHERE source_node LIKE ? OR target_node LIKE ?",
            (prefix + "%", prefix + "%"),
        )
        conn.commit()
        conn.close()

def test_incident_report():
    assert os.path.isfile(REPORT_PATH), f"Incident report missing: {REPORT_PATH}"

    target_node = "backup-server-delta"
    oracle_proc = run_oracle(target_node)
    assert oracle_proc.returncode == 0, f"Oracle failed for incident node:\n{oracle_proc.stderr}"
    expected_out = oracle_proc.stdout.strip()

    with open(REPORT_PATH, "r") as f:
        report_out = f.read().strip()

    assert report_out == expected_out, (
        f"Incident report content does not match expected output for node '{target_node}'.\n"
        f"Expected:\n{expected_out}\n\n"
        f"Got:\n{report_out}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
