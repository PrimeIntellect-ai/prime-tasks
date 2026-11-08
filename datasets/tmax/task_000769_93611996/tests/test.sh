#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import time
import random
import pytest


def test_database_and_data():
    db_path = '/home/user/network.db'
    assert os.path.exists(db_path), f"Database {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='topology'")
    assert cur.fetchone() is not None, "Table 'topology' does not exist in the database."

    cur.execute("SELECT parent_node, child_node FROM topology ORDER BY child_node")
    rows = cur.fetchall()

    # Re-derive expected edges based on the video generation logic.
    expected_edges = []
    for f in range(1000):
        if f % 3 == 0:
            expected_edges.append(((f * 7) % 100, f))

    assert len(rows) == len(expected_edges), f"Expected {len(expected_edges)} edges in topology, got {len(rows)}."
    for expected, actual in zip(expected_edges, rows):
        assert expected == actual, f"Data mismatch. Expected edge {expected}, got {actual}."

    # Recursive traversal and root discovery need indexes beginning with each
    # lookup column, not merely an unrelated index.
    cur.execute("PRAGMA index_list('topology')")
    index_names = [row[1] for row in cur.fetchall()]
    leading_columns = []
    for name in index_names:
        quoted = '"' + name.replace('"', '""') + '"'
        cur.execute(f"PRAGMA index_info({quoted})")
        columns = [row[2] for row in sorted(cur.fetchall(), key=lambda row: row[0])]
        if columns:
            leading_columns.append(columns[0])

    assert 'parent_node' in leading_columns, "Missing an index beginning with parent_node."
    assert 'child_node' in leading_columns, "Missing an index beginning with child_node."
    conn.close()


def load_query():
    sql_path = '/home/user/analyze_hierarchy.sql'
    assert os.path.isfile(sql_path), f"SQL file {sql_path} does not exist."
    with open(sql_path, 'r') as f:
        query = f.read().strip()
    assert query, "SQL query file is empty."

    without_comments = re.sub(r'/\*.*?\*/', ' ', query, flags=re.S)
    without_comments = re.sub(r'--[^\n]*', ' ', without_comments)
    assert re.search(r'\bWITH\s+RECURSIVE\b', without_comments, flags=re.I), \
        "The query must use WITH RECURSIVE."
    return query


def expected_hierarchy(edges):
    parents = {p for p, _ in edges}
    children = {c for _, c in edges}
    roots = parents - children
    depths = {root: 0 for root in roots}

    # All verifier graphs are DAGs. Repeated relaxation derives the longest
    # root-to-node depth independently of the submitted query.
    for _ in range(len(parents | children) + 1):
        changed = False
        for parent, child in edges:
            if parent in depths:
                candidate = depths[parent] + 1
                if candidate > depths.get(child, -1):
                    depths[child] = candidate
                    changed = True
        if not changed:
            break
    return sorted(depths.items())


def execute_and_check(conn, query, expected):
    cur = conn.cursor()
    cur.execute(query)
    assert cur.description is not None, "Query did not produce a result set."
    names = [column[0].lower() for column in cur.description]
    assert names == ['node_id', 'max_depth'], \
        f"Expected columns node_id and max_depth, got {names}."
    results = cur.fetchall()
    assert results == expected, \
        f"Query must return every node at its maximum depth in ascending node_id order."
    return results


def test_recursive_query_on_nontrivial_hierarchy():
    query = load_query()
    conn = sqlite3.connect(':memory:')
    cur = conn.cursor()
    cur.execute("CREATE TABLE topology (parent_node INTEGER, child_node INTEGER)")

    rng = random.Random(734921)
    labels = list(range(1000003, 1000003 + 240 * 37, 37))
    rng.shuffle(labels)
    edges = []

    # Two independent, non-contiguous hierarchies, including multiple paths to
    # some nodes. The long chain prevents a fixed number of self-joins from
    # substituting for recursive traversal.
    for start, length in ((0, 180), (180, 60)):
        for i in range(start + 1, start + length):
            edges.append((labels[i - 1], labels[i]))
            if i >= start + 3 and i % 4 == 0:
                edges.append((labels[i - 3], labels[i]))
            if i >= start + 7 and i % 9 == 0:
                edges.append((labels[i - 7], labels[i]))

    cur.executemany("INSERT INTO topology VALUES (?, ?)", edges)
    conn.commit()

    try:
        cur.execute("EXPLAIN QUERY PLAN " + query)
        plan = ' '.join(str(row[3]) for row in cur.fetchall()).upper()
    except Exception as e:
        pytest.fail(f"SQL query could not be planned: {e}")
    assert 'RECURSIVE STEP' in plan, "The submitted CTE does not perform a recursive step."

    expected = expected_hierarchy(edges)
    try:
        execute_and_check(conn, query, expected)
    except Exception as e:
        if isinstance(e, AssertionError):
            raise
        pytest.fail(f"SQL execution failed with error: {e}")
    finally:
        conn.close()


def test_sql_query_performance_and_correctness():
    query = load_query()
    db_path = '/tmp/test_perf.db'
    if os.path.exists(db_path):
        os.remove(db_path)

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("CREATE TABLE topology (parent_node INTEGER, child_node INTEGER)")

    # Generate a large conventional binary tree with 99,999 edges and 100,000 nodes.
    edges = []
    for i in range(1, 100000):
        parent = (i - 1) // 2
        edges.append((parent, i))

    cur.executemany("INSERT INTO topology VALUES (?, ?)", edges)
    conn.commit()

    expected = [(i, (i + 1).bit_length() - 1) for i in range(100000)]
    start_time = time.time()
    try:
        results = execute_and_check(conn, query, expected)
    except Exception as e:
        if isinstance(e, AssertionError):
            raise
        pytest.fail(f"SQL execution failed with error: {e}")
    finally:
        conn.close()
    exec_time = time.time() - start_time

    assert len(results) > 0, "Query returned no results."
    dict_res = {row[0]: row[1] for row in results}
    assert dict_res.get(0) == 0, f"Root node 0 should have max_depth 0, got {dict_res.get(0)}"
    assert dict_res.get(99999) == 16, f"Node 99999 should have max_depth 16, got {dict_res.get(99999)}"
    assert exec_time <= 0.5, f"Execution time {exec_time:.4f} seconds exceeds the threshold of 0.5 seconds."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
