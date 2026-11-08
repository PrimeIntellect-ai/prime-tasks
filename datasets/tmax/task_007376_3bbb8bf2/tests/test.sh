#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import os
import random
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

DB_PATH = '/home/user/etl_lineage.db'
RESULT_PATH = '/home/user/pipeline_result.json'
SCRIPT_PATH = '/home/user/optimize_and_query.py'


def load_result():
    assert os.path.exists(RESULT_PATH), f"Result file {RESULT_PATH} does not exist."
    assert os.path.isfile(RESULT_PATH), f"Path {RESULT_PATH} is not a file."
    with open(RESULT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULT_PATH} does not contain valid JSON.")


def user_indexes(conn):
    rows = conn.execute("PRAGMA index_list('dependencies')").fetchall()
    return [row[1] for row in rows if not row[1].startswith('sqlite_autoindex')]


def index_columns(conn, name):
    escaped = name.replace("'", "''")
    return [row[2] for row in conn.execute(f"PRAGMA index_info('{escaped}')").fetchall()]


def assert_result_matches_database(data, expected_cost):
    assert "created_indexes" in data, "JSON missing 'created_indexes' key."
    assert "query_plan" in data, "JSON missing 'query_plan' key."
    assert "min_transfer_cost" in data, "JSON missing 'min_transfer_cost' key."
    assert data["min_transfer_cost"] == expected_cost, (
        f"Expected min_transfer_cost to be {expected_cost}, got {data['min_transfer_cost']}"
    )

    created = data["created_indexes"]
    assert isinstance(created, list), "'created_indexes' must be a list."
    assert len(created) > 0, "'created_indexes' list is empty. Expected at least one index."
    assert all(isinstance(name, str) and name for name in created), (
        "Every created_indexes entry must be a non-empty index name."
    )

    plan = data["query_plan"]
    assert isinstance(plan, str), "'query_plan' must be a string."
    plan_upper = plan.upper()
    assert "SEARCH" in plan_upper or "INDEX" in plan_upper, (
        "query_plan does not seem to indicate index usage (missing 'SEARCH' or 'INDEX')."
    )
    assert "RECURSIVE STEP" in plan_upper, (
        "query_plan is not the output of EXPLAIN QUERY PLAN for a recursive CTE."
    )

    with sqlite3.connect(DB_PATH) as conn:
        actual = user_indexes(conn)
        assert actual, "No user-created indexes found on the 'dependencies' table."
        assert all(name in actual for name in created), (
            "created_indexes contains a name that is not an actual dependencies index."
        )
        source_indexes = [name for name in created if index_columns(conn, name)[:1] == ['source_task']]
        assert source_indexes, (
            "No reported index has source_task as its first column."
        )
        assert any(name.upper() in plan_upper for name in source_indexes), (
            "query_plan does not reference a reported source_task index."
        )


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file."
    assert not os.path.islink(SCRIPT_PATH), f"Script {SCRIPT_PATH} must be a regular file."

    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    source_upper = source.upper()
    assert 'SQLITE3' in source_upper, "The script must use the sqlite3 module."
    assert 'WITH RECURSIVE' in source_upper, "The script must execute a recursive CTE."
    assert 'EXPLAIN QUERY PLAN' in source_upper, "The script must execute EXPLAIN QUERY PLAN."
    assert 'CREATE INDEX' in source_upper or 'CREATE UNIQUE INDEX' in source_upper, (
        "The script must create an index."
    )

    completed = subprocess.run(
        ['python3', SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=90,
    )
    assert completed.returncode == 0, (
        f"Running {SCRIPT_PATH} failed with exit code {completed.returncode}:\n{completed.stderr}"
    )


def test_result_file_exists_and_valid():
    data = load_result()
    assert "created_indexes" in data, "JSON missing 'created_indexes' key."
    assert "query_plan" in data, "JSON missing 'query_plan' key."
    assert "min_transfer_cost" in data, "JSON missing 'min_transfer_cost' key."


def test_min_transfer_cost():
    data = load_result()
    assert data["min_transfer_cost"] == 40, (
        f"Expected min_transfer_cost to be 40, got {data['min_transfer_cost']}"
    )


def test_created_indexes_info():
    data = load_result()
    created_indexes = data["created_indexes"]
    assert isinstance(created_indexes, list), "'created_indexes' must be a list."
    assert len(created_indexes) > 0, "'created_indexes' list is empty. Expected at least one index."


def test_query_plan_indicates_index_usage():
    data = load_result()
    query_plan = data["query_plan"]
    assert isinstance(query_plan, str), "'query_plan' must be a string."
    plan_upper = query_plan.upper()
    assert "SEARCH" in plan_upper or "INDEX" in plan_upper, (
        "query_plan does not seem to indicate index usage (missing 'SEARCH' or 'INDEX')."
    )


def test_database_has_correct_index():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."
    with sqlite3.connect(DB_PATH) as conn:
        indexes = user_indexes(conn)
        assert len(indexes) > 0, "No user-created indexes found on the 'dependencies' table."
        assert any(index_columns(conn, name)[:1] == ['source_task'] for name in indexes), (
            "No index found where the first column is 'source_task'."
        )


def test_reported_indexes_and_recursive_plan_are_real():
    assert_result_matches_database(load_result(), 40)


def shortest_path(edges):
    graph = {}
    for source, target, cost in edges:
        graph.setdefault(source, []).append((target, cost))
    distances = {0: 0}
    queue = [(0, 0)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances[node]:
            continue
        if node == 9999:
            return distance
        for target, cost in graph.get(node, []):
            candidate = distance + cost
            if candidate < distances.get(target, float('inf')):
                distances[target] = candidate
                heapq.heappush(queue, (candidate, target))
    return None


def test_script_computes_a_non_hardcoded_recursive_result():
    temp_dir = tempfile.mkdtemp(prefix='etl_verifier_')
    saved_db = os.path.join(temp_dir, 'original.db')
    saved_result = os.path.join(temp_dir, 'original_result.json')
    had_result = os.path.exists(RESULT_PATH)

    os.replace(DB_PATH, saved_db)
    if had_result:
        os.replace(RESULT_PATH, saved_result)

    try:
        rng = random.SystemRandom()
        a, b = rng.randint(2, 12), rng.randint(13, 29)
        c, d, e = rng.randint(20, 35), rng.randint(20, 35), rng.randint(20, 35)
        direct = a + b + rng.randint(30, 70)
        edges = [
            (0, 101, a),
            (101, 9999, b),
            (0, 202, c),
            (202, 303, d),
            (303, 9999, e),
            (0, 9999, direct),
            (101, 404, rng.randint(40, 80)),
            (404, 9999, rng.randint(40, 80)),
            (500, 600, 1),
        ]
        expected = shortest_path(edges)
        assert expected is not None and expected != 40

        with sqlite3.connect(DB_PATH) as conn:
            conn.execute('''CREATE TABLE dependencies (
                id INTEGER PRIMARY KEY,
                source_task INTEGER,
                target_task INTEGER,
                transfer_cost INTEGER
            )''')
            conn.executemany(
                'INSERT INTO dependencies (source_task, target_task, transfer_cost) VALUES (?, ?, ?)',
                edges,
            )
            conn.commit()

        completed = subprocess.run(
            ['python3', SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert completed.returncode == 0, (
            f"Script failed on a valid alternate DAG: {completed.stderr}"
        )

        with sqlite3.connect(DB_PATH) as conn:
            after_edges = conn.execute(
                'SELECT source_task, target_task, transfer_cost FROM dependencies ORDER BY id'
            ).fetchall()
        assert after_edges == edges, "The script modified data in the dependencies table."

        data = load_result()
        assert_result_matches_database(data, expected)
    finally:
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
        if os.path.exists(RESULT_PATH):
            os.remove(RESULT_PATH)
        os.replace(saved_db, DB_PATH)
        if had_result:
            os.replace(saved_result, RESULT_PATH)
        shutil.rmtree(temp_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
