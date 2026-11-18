#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
import sys
import tempfile

import pytest

DB_PATH = '/home/user/activity.db'
ETL_SCRIPT_PATH = '/home/user/etl_graph.py'
GRAPH_JSON_PATH = '/home/user/graph_materialized.json'
TOP_INFLUENCER_PATH = '/home/user/top_influencer.txt'


def compute_expected(db_path):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    c.execute("SELECT user_id, name FROM users ORDER BY user_id")
    nodes = [{"id": row["user_id"], "name": row["name"]} for row in c.fetchall()]

    c.execute("""
        SELECT c.commenter_id AS source, p.author_id AS target, COUNT(*) AS weight
        FROM comments c
        JOIN posts p ON c.post_id = p.post_id
        WHERE c.commenter_id != p.author_id
        GROUP BY c.commenter_id, p.author_id
    """)
    edges = [
        {"source": row["source"], "target": row["target"], "weight": row["weight"]}
        for row in c.fetchall()
    ]

    c.execute("""
        SELECT p.author_id, COUNT(*) AS total_weight
        FROM comments c
        JOIN posts p ON c.post_id = p.post_id
        WHERE c.commenter_id != p.author_id
        GROUP BY p.author_id
        ORDER BY total_weight DESC, p.author_id ASC
        LIMIT 1
    """)
    row = c.fetchone()
    top_influencer = str(row["author_id"]) if row else None
    conn.close()
    return {"nodes": nodes, "edges": edges, "top_influencer": top_influencer}


@pytest.fixture(scope="module")
def db_data():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."
    return compute_expected(DB_PATH)


def test_etl_script_exists():
    assert os.path.exists(ETL_SCRIPT_PATH), f"ETL script {ETL_SCRIPT_PATH} is missing."
    assert os.path.isfile(ETL_SCRIPT_PATH), f"{ETL_SCRIPT_PATH} is not a file."


def test_indexes_created():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%';")
    indexes = c.fetchall()

    assert len(indexes) > 0, "No new indexes were created in the database."
    indexed_tables = {row[1] for row in indexes}
    assert "comments" in indexed_tables or "posts" in indexed_tables, \
        "Expected indexes on 'comments' or 'posts' tables to optimize the query."

    relevant = False
    for index_name, table_name in indexes:
        escaped_name = index_name.replace("'", "''")
        c.execute(f"PRAGMA index_info('{escaped_name}')")
        columns = {row[2] for row in c.fetchall()}
        if table_name == "comments" and columns.intersection({"post_id", "commenter_id"}):
            relevant = True
        if table_name == "posts" and "author_id" in columns:
            relevant = True
    conn.close()
    assert relevant, "The created indexes do not cover columns used by the interaction query."


def test_graph_materialized(db_data):
    assert os.path.exists(GRAPH_JSON_PATH), f"Output JSON file {GRAPH_JSON_PATH} is missing."

    with open(GRAPH_JSON_PATH, 'r') as f:
        try:
            graph = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {GRAPH_JSON_PATH} is not valid JSON.")

    assert "nodes" in graph, f"Key 'nodes' missing in {GRAPH_JSON_PATH}"
    assert "edges" in graph, f"Key 'edges' missing in {GRAPH_JSON_PATH}"

    expected_nodes = sorted(db_data["nodes"], key=lambda x: x["id"])
    actual_nodes = sorted(graph["nodes"], key=lambda x: x.get("id", -1))
    assert actual_nodes == expected_nodes, "The 'nodes' array does not match the expected state."

    expected_edges = sorted(db_data["edges"], key=lambda x: (x["source"], x["target"]))
    actual_edges = sorted(graph["edges"], key=lambda x: (x.get("source", -1), x.get("target", -1)))
    assert actual_edges == expected_edges, "The 'edges' array does not match the expected state (weights or connections are incorrect)."


def test_top_influencer(db_data):
    assert os.path.exists(TOP_INFLUENCER_PATH), f"File {TOP_INFLUENCER_PATH} is missing."

    with open(TOP_INFLUENCER_PATH, 'r') as f:
        content = f.read().strip()

    assert content == db_data["top_influencer"], \
        f"Expected top influencer ID '{db_data['top_influencer']}', but found '{content}' in {TOP_INFLUENCER_PATH}."


def test_etl_script_executes_on_unseen_database():
    temp_dir = tempfile.mkdtemp(prefix='etl-verifier-')
    db_backup = os.path.join(temp_dir, 'activity.db')
    shutil.copy2(DB_PATH, db_backup)

    saved_outputs = {}
    for path in (GRAPH_JSON_PATH, TOP_INFLUENCER_PATH):
        if os.path.exists(path):
            with open(path, 'rb') as f:
                saved_outputs[path] = f.read()

    try:
        for path in (DB_PATH, DB_PATH + '-wal', DB_PATH + '-shm'):
            if os.path.exists(path):
                os.remove(path)

        base = 100000 + secrets.randbelow(800000)
        u1, u2, u3, u4 = base, base + 7, base + 19, base + 31
        token = secrets.token_hex(6)

        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        c.execute('CREATE TABLE users (user_id INTEGER PRIMARY KEY, name TEXT)')
        c.execute('CREATE TABLE posts (post_id INTEGER PRIMARY KEY, author_id INTEGER, content TEXT)')
        c.execute('CREATE TABLE comments (comment_id INTEGER PRIMARY KEY, post_id INTEGER, commenter_id INTEGER, content TEXT)')
        c.executemany('INSERT INTO users VALUES (?, ?)', [
            (u1, 'Alpha-' + token), (u2, 'Beta-' + token),
            (u3, 'Gamma-' + token), (u4, 'Isolated-' + token)
        ])
        posts = [(base + 1000, u1, 'p1'), (base + 1001, u2, 'p2'), (base + 1002, u3, 'p3')]
        c.executemany('INSERT INTO posts VALUES (?, ?, ?)', posts)

        comments = []
        cid = base + 2000
        for _ in range(4):
            comments.append((cid, base + 1000, u2, 'u2 to u1'))
            cid += 1
        for _ in range(2):
            comments.append((cid, base + 1000, u3, 'u3 to u1'))
            cid += 1
        comments.append((cid, base + 1001, u1, 'u1 to u2'))
        cid += 1
        for _ in range(5):
            comments.append((cid, base + 1002, u3, 'self comment'))
            cid += 1
        c.executemany('INSERT INTO comments VALUES (?, ?, ?, ?)', comments)
        conn.commit()
        conn.close()

        expected = compute_expected(DB_PATH)
        for path in (GRAPH_JSON_PATH, TOP_INFLUENCER_PATH):
            if os.path.exists(path):
                os.remove(path)

        result = subprocess.run(
            [sys.executable, ETL_SCRIPT_PATH],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, \
            f"ETL script failed when executed (exit {result.returncode}): {result.stderr}"
        assert os.path.isfile(GRAPH_JSON_PATH), "Executing the ETL script did not create the graph JSON."
        assert os.path.isfile(TOP_INFLUENCER_PATH), "Executing the ETL script did not create the influencer file."

        with open(GRAPH_JSON_PATH, 'r') as f:
            graph = json.load(f)
        actual_nodes = sorted(graph.get('nodes', []), key=lambda x: x.get('id', -1))
        actual_edges = sorted(graph.get('edges', []), key=lambda x: (x.get('source', -1), x.get('target', -1)))
        expected_nodes = sorted(expected['nodes'], key=lambda x: x['id'])
        expected_edges = sorted(expected['edges'], key=lambda x: (x['source'], x['target']))
        assert actual_nodes == expected_nodes, "Executed ETL script did not project all users from the unseen database."
        assert actual_edges == expected_edges, "Executed ETL script did not compute the weighted interaction graph from the unseen database."

        with open(TOP_INFLUENCER_PATH, 'r') as f:
            influencer = f.read().strip()
        assert influencer == expected['top_influencer'], \
            "Executed ETL script did not compute the top influencer from the unseen database."
    finally:
        for path in (DB_PATH, DB_PATH + '-wal', DB_PATH + '-shm'):
            if os.path.exists(path):
                os.remove(path)
        shutil.copy2(db_backup, DB_PATH)
        for path in (GRAPH_JSON_PATH, TOP_INFLUENCER_PATH):
            if path in saved_outputs:
                with open(path, 'wb') as f:
                    f.write(saved_outputs[path])
            elif os.path.exists(path):
                os.remove(path)
        shutil.rmtree(temp_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
