#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import pytest

DB_PATH = "/home/user/graph_backup.db"
SUMMARY_PATH = "/home/user/stale_summary.txt"
CYPHER_PATH = "/home/user/cleanup.cypher"
SCRIPT_PATH = "/home/user/analyze_graph.py"


def get_stale_edges():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    query = """
        SELECT e.edge_id, e.source_id, e.rel_type
        FROM edges e
        JOIN nodes n ON e.source_id = n.node_id
        WHERE e.target_id NOT IN (SELECT node_id FROM nodes)
        ORDER BY e.edge_id ASC
    """
    cursor.execute(query)
    stale_edges = cursor.fetchall()
    conn.close()
    return stale_edges


def run_submission():
    for path in (SUMMARY_PATH, CYPHER_PATH):
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def expected_summary(stale_edges):
    counts = {}
    for _, _, rel_type in stale_edges:
        counts[rel_type] = counts.get(rel_type, 0) + 1
    return [f"{rel}: {counts[rel]}" for rel in sorted(counts.keys())]


def expected_cypher(stale_edges):
    return [
        f"MATCH (s)-[r:{rel_type}]->() WHERE s.node_id = {source_id} AND r.edge_backup_id = {edge_id} DELETE r;"
        for edge_id, source_id, rel_type in stale_edges
    ]


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


@pytest.fixture(scope="session", autouse=True)
def execute_submission_on_original_database():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} was not created."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    run_submission()


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} was not created."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."


def test_stale_summary():
    assert os.path.exists(SUMMARY_PATH), f"Summary file {SUMMARY_PATH} is missing."

    stale_edges = get_stale_edges()
    expected_lines = expected_summary(stale_edges)
    actual_lines = read_nonempty_lines(SUMMARY_PATH)

    assert actual_lines == expected_lines, (
        f"Contents of {SUMMARY_PATH} do not match expected.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )


def test_cleanup_cypher():
    assert os.path.exists(CYPHER_PATH), f"Cypher script {CYPHER_PATH} is missing."

    stale_edges = get_stale_edges()
    expected_lines = expected_cypher(stale_edges)
    actual_lines = read_nonempty_lines(CYPHER_PATH)

    assert actual_lines == expected_lines, (
        f"Contents of {CYPHER_PATH} do not match expected.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )


def test_script_recomputes_outputs_from_database():
    fd, backup_path = tempfile.mkstemp(prefix="graph_backup_", suffix=".db")
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)

    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT COALESCE(MAX(node_id), 0) FROM nodes")
        source_id = cursor.fetchone()[0] + 1000000
        target_id = source_id + 1
        cursor.execute("SELECT COALESCE(MAX(edge_id), 0) FROM edges")
        edge_id = cursor.fetchone()[0] + 1000000
        random_rel_type = "VERIFY_" + secrets.token_hex(6).upper()

        cursor.execute("INSERT INTO nodes (node_id) VALUES (?)", (source_id,))
        cursor.executemany(
            "INSERT INTO edges (edge_id, source_id, target_id, rel_type) VALUES (?, ?, ?, ?)",
            [
                (edge_id, source_id, target_id, random_rel_type),
                (edge_id + 1, source_id, target_id + 1, "KNOWS"),
                (edge_id + 2, source_id, 1, random_rel_type),
            ],
        )
        conn.commit()
        conn.close()

        stale_edges = get_stale_edges()
        expected_summary_lines = expected_summary(stale_edges)
        expected_cypher_lines = expected_cypher(stale_edges)

        run_submission()

        assert os.path.exists(SUMMARY_PATH), f"Summary file {SUMMARY_PATH} is missing after execution."
        assert os.path.exists(CYPHER_PATH), f"Cypher script {CYPHER_PATH} is missing after execution."
        assert read_nonempty_lines(SUMMARY_PATH) == expected_summary_lines
        assert read_nonempty_lines(CYPHER_PATH) == expected_cypher_lines
    finally:
        os.replace(backup_path, DB_PATH)
        subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=20,
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
