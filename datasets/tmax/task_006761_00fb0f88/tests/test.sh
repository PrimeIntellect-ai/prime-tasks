#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import sqlite3
import subprocess
import tempfile

import pytest

DB_PATH = '/home/user/graph.db'
RESULTS_PATH = '/home/user/optimized_results.json'
QUERY_PLAN_PATH = '/home/user/query_plan.txt'
SCRIPT_PATH = '/home/user/fast_pipeline.py'


def test_database_index():
    """Verify that an index was created on the Edges table for source_id."""
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    c.execute("PRAGMA index_list('Edges')")
    indexes = c.fetchall()
    assert indexes, "No index found on the 'Edges' table."

    valid_index_found = False
    for idx in indexes:
        idx_name = idx[1]
        escaped_name = idx_name.replace("'", "''")
        c.execute(f"PRAGMA index_info('{escaped_name}')")
        columns = [row[2] for row in c.fetchall()]
        if columns and columns[0] == 'source_id':
            valid_index_found = True
            break

    conn.close()
    assert valid_index_found, "An index on 'Edges' starting with 'source_id' is required."


def test_optimized_results_json():
    """Verify the contents of the generated JSON file."""
    assert os.path.isfile(RESULTS_PATH), f"Expected JSON file {RESULTS_PATH} is missing."

    with open(RESULTS_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} does not contain valid JSON.")

    expected_data = {
        "S1": ["D1", "D2", "Q1", "S2"],
        "S2": ["D1", "D2", "Q1"],
        "S3": ["A1", "A2", "D2"]
    }

    assert data == expected_data, f"JSON contents do not match expected output. Got: {data}"


def test_query_plan_log():
    """Verify the query plan log exists and shows index usage."""
    assert os.path.isfile(QUERY_PLAN_PATH), f"Query plan log {QUERY_PLAN_PATH} is missing."

    with open(QUERY_PLAN_PATH, 'r') as f:
        content = f.read().lower()

    assert content.strip() != "", "Query plan log is empty."
    assert "index" in content, "Query plan does not appear to use an index (missing 'INDEX' keyword)."


def test_python_script_exists_and_recursive():
    """Verify the Python script exists, is executable, and uses a Recursive CTE."""
    assert os.path.isfile(SCRIPT_PATH), f"Python script {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Python script {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, 'r') as f:
        content = f.read().lower()

    assert "with recursive" in content, "The Python script must contain a 'WITH RECURSIVE' SQL statement."


def _expected_results(conn):
    services = [row[0] for row in conn.execute(
        "SELECT id FROM Nodes WHERE type = 'Service'"
    )]
    adjacency = {}
    for source, target in conn.execute(
        "SELECT source_id, target_id FROM Edges WHERE relation_type = 'depends_on'"
    ):
        adjacency.setdefault(source, []).append(target)

    expected = {}
    for service in services:
        reached = set()
        frontier = {service}
        for _depth in range(3):
            next_frontier = set()
            for source in frontier:
                next_frontier.update(adjacency.get(source, ()))
            reached.update(next_frontier)
            frontier = next_frontier
        reached.discard(service)
        expected[service] = sorted(reached)
    return expected


def test_pipeline_executes_on_unseen_graph():
    """Execute the submitted artifact and verify fresh recursive results."""
    backup_path = tempfile.mktemp(prefix='graph-backup-', suffix='.db')
    with sqlite3.connect(DB_PATH) as source, sqlite3.connect(backup_path) as backup:
        source.backup(backup)

    saved_outputs = {}
    for path in (RESULTS_PATH, QUERY_PLAN_PATH):
        if os.path.isfile(path):
            with open(path, 'rb') as f:
                saved_outputs[path] = f.read()

    try:
        tag = secrets.token_hex(10)
        service = f"T_SERVICE_{tag}"
        empty_service = f"T_EMPTY_{tag}"
        n1 = f"T_N1_{tag}"
        n2 = f"T_N2_{tag}"
        n3 = f"T_N3_{tag}"
        n4 = f"T_N4_{tag}"
        ignored = f"T_IGNORED_{tag}"

        with sqlite3.connect(DB_PATH) as conn:
            conn.executemany(
                "INSERT INTO Nodes(id, type) VALUES (?, ?)",
                [
                    (service, 'Service'),
                    (empty_service, 'Service'),
                    (n1, 'Component'),
                    (n2, 'Component'),
                    (n3, 'Component'),
                    (n4, 'Component'),
                    (ignored, 'Component'),
                ],
            )
            conn.executemany(
                "INSERT INTO Edges(source_id, target_id, relation_type) VALUES (?, ?, ?)",
                [
                    (service, n1, 'depends_on'),
                    (n1, n2, 'depends_on'),
                    (n2, n3, 'depends_on'),
                    (n3, n4, 'depends_on'),
                    (n1, service, 'depends_on'),
                    (service, ignored, 'communicates_with'),
                ],
            )
            conn.commit()
            expected = _expected_results(conn)

        for path in (RESULTS_PATH, QUERY_PLAN_PATH):
            if os.path.exists(path):
                os.remove(path)

        completed = subprocess.run(
            [SCRIPT_PATH],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert completed.returncode == 0, (
            f"Pipeline failed with exit code {completed.returncode}. "
            f"stdout: {completed.stdout!r}; stderr: {completed.stderr!r}"
        )

        assert os.path.isfile(RESULTS_PATH), "Pipeline did not create optimized_results.json."
        with open(RESULTS_PATH, 'r') as f:
            actual = json.load(f)
        assert actual == expected, f"Pipeline produced incorrect results for an unseen graph. Got: {actual}"

        assert os.path.isfile(QUERY_PLAN_PATH), "Pipeline did not create query_plan.txt."
        with open(QUERY_PLAN_PATH, 'r') as f:
            plan = f.read().lower()
        assert plan.strip(), "Pipeline created an empty query plan."
        assert "index" in plan, "Fresh query plan does not show index usage."
    finally:
        with sqlite3.connect(backup_path) as backup, sqlite3.connect(DB_PATH) as destination:
            backup.backup(destination)
        if os.path.exists(backup_path):
            os.remove(backup_path)
        for path in (RESULTS_PATH, QUERY_PLAN_PATH):
            if path in saved_outputs:
                with open(path, 'wb') as f:
                    f.write(saved_outputs[path])
            elif os.path.exists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
