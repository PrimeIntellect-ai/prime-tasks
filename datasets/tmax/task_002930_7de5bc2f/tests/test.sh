#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import sqlite3
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/query_filter.py"
SQL_PATH = "/home/user/centrality.sql"
DB_PATH = "/app/backup_graph.db"


def run_filter(query):
    fd, path = tempfile.mkstemp(prefix="cypher_" + secrets.token_hex(6) + "_", suffix=".txt")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(query)
        return subprocess.run(["python3", SCRIPT_PATH, path], capture_output=True).returncode
    finally:
        os.unlink(path)


def test_query_filter_evil_corpus():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    evil_dir = "/verify/corpus/evil/"
    assert os.path.isdir(evil_dir), f"Evil corpus directory not found at {evil_dir}"

    evil_files = [f for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    bypassed = []

    for filename in evil_files:
        filepath = os.path.join(evil_dir, filename)
        result = subprocess.run(["python3", SCRIPT_PATH, filepath], capture_output=True)
        if result.returncode != 1:
            bypassed.append(filename)

    assert not bypassed, f"{len(bypassed)} of {len(evil_files)} evil bypassed: {bypassed}"


def test_query_filter_clean_corpus():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    clean_dir = "/verify/corpus/clean/"
    assert os.path.isdir(clean_dir), f"Clean corpus directory not found at {clean_dir}"

    clean_files = [f for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    modified = []

    for filename in clean_files:
        filepath = os.path.join(clean_dir, filename)
        result = subprocess.run(["python3", SCRIPT_PATH, filepath], capture_output=True)
        if result.returncode != 0:
            modified.append(filename)

    assert not modified, f"{len(modified)} of {len(clean_files)} clean modified (failed): {modified}"


def test_query_filter_runtime_generated_queries():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    a, b, c = ["v_" + secrets.token_hex(7) for _ in range(3)]
    label1, label2 = ["L" + secrets.token_hex(5) for _ in range(2)]

    evil_queries = [
        f"MATCH ({a}), ({b})\nRETURN {a}, {b}\n",
        f"mAtCh\n  ({a}:{label1})   ,\n ({b}:{label2})\nReTuRn {a}, {b}\n",
        f"MATCH ({a})-[:DEPENDS_ON]->({b}), ({c})\nRETURN {a}, {b}, {c}\n",
    ]
    clean_queries = [
        f"MATCH ({a})-[:DEPENDS_ON]->({b})\nRETURN {a}, {b}\n",
        f"MaTcH ({a}:{label1})\n  mAtCh ({b}:{label2})\nRETURN {a}, {b}\n",
        f"MATCH ({a}) <- [:{label1}] - ({b}) -[:{label2}]-> ({c})\nRETURN {a}, {b}, {c}\n",
    ]

    cases = [(q, 1, "evil") for q in evil_queries] + [(q, 0, "clean") for q in clean_queries]
    random.SystemRandom().shuffle(cases)
    failures = []
    for query, expected_code, classification in cases:
        actual_code = run_filter(query)
        if actual_code != expected_code:
            failures.append((classification, expected_code, actual_code, query))

    assert not failures, f"Generated Cypher cases were misclassified: {failures}"


def read_sql():
    assert os.path.exists(SQL_PATH), f"SQL file not found at {SQL_PATH}"
    with open(SQL_PATH, "r") as f:
        return f.read()


def test_sql_centrality():
    assert os.path.exists(SQL_PATH), f"SQL file not found at {SQL_PATH}"
    assert os.path.exists(DB_PATH), f"Database not found at {DB_PATH}"

    sql_query = read_sql()
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    try:
        cursor.execute(sql_query)
        results = cursor.fetchall()
    except sqlite3.Error as e:
        pytest.fail(f"SQL execution failed: {e}")
    finally:
        conn.close()

    expected = [
        ('jobA', 2, 1),
        ('jobC', 2, 1),
        ('jobB', 1, 3),
        ('jobD', 1, 3)
    ]

    assert results == expected, f"Expected {expected}, but got {results}"


def expected_centrality(nodes, edges):
    degrees = {node: 0 for node in nodes}
    for source, target in edges:
        degrees[source] += 1
        degrees[target] += 1

    ordered = sorted(nodes, key=lambda node: (-degrees[node], node))
    results = []
    for node in ordered:
        rank = 1 + sum(1 for other in nodes if degrees[other] > degrees[node])
        results.append((node, degrees[node], rank))
    return results


def test_sql_runtime_generated_graphs_and_window_function():
    sql_query = read_sql()
    assert re.search(r"\brank\s*\(\s*\)\s*over\b", sql_query, re.IGNORECASE | re.DOTALL), \
        "centrality.sql must use the RANK window function"

    rng = random.SystemRandom()
    for _ in range(3):
        node_count = rng.randint(7, 10)
        nodes = ["job_" + secrets.token_hex(7) for _ in range(node_count)]

        # The final node is deliberately isolated; the remaining topology is
        # generated only after the agent has finished running.
        edges = []
        for source in nodes[:-1]:
            for target in nodes[:-1]:
                if source != target and rng.random() < 0.22:
                    edges.append((source, target))
        if not edges:
            edges.extend([(nodes[0], nodes[1]), (nodes[0], nodes[2])])

        fd, db_path = tempfile.mkstemp(prefix="graph_" + secrets.token_hex(5) + "_", suffix=".db")
        os.close(fd)
        try:
            conn = sqlite3.connect(db_path)
            conn.execute("CREATE TABLE nodes (job_id TEXT PRIMARY KEY)")
            conn.execute("CREATE TABLE edges (source_job TEXT, target_job TEXT)")
            conn.executemany("INSERT INTO nodes(job_id) VALUES (?)", [(node,) for node in nodes])
            conn.executemany("INSERT INTO edges(source_job, target_job) VALUES (?, ?)", edges)
            conn.commit()

            try:
                cursor = conn.cursor()
                cursor.execute(sql_query)
                results = cursor.fetchall()
                columns = [description[0] for description in cursor.description]
            except sqlite3.Error as e:
                pytest.fail(f"SQL execution failed on generated graph: {e}")
            finally:
                conn.close()

            expected = expected_centrality(nodes, edges)
            assert columns == ["job_id", "centrality", "centrality_rank"], \
                f"Unexpected output columns: {columns}"
            assert results == expected, f"Expected {expected}, but got {results}"
        finally:
            os.unlink(db_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
