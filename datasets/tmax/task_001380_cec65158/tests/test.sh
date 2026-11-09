#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import subprocess

import networkx as nx
import pytest
import requests

DB_PATH = "/home/user/backups.db"
KEY_DERIVER_PATH = "/app/key_deriver"
URL = "http://127.0.0.1:8000/critical_keys"
QUERY = """SELECT j1.id, j2.id
FROM jobs j1
JOIN deps d ON j1.id = d.source
JOIN jobs j2 ON d.target = j2.id
WHERE j1.type = 'incremental' AND j2.type = 'full';"""


def _quote_identifier(value):
    return '"' + value.replace('"', '""') + '"'


def test_database_indexes():
    """Verify that a relevant deps index exists and is used by the target query."""
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND tbl_name='deps';")
        indexes = cursor.fetchall()

        # Preserve the original assertion that an index was created on deps.
        assert len(indexes) > 0, "No indexes found on the 'deps' table. You must create an index to optimize the query."

        usable_names = []
        for name, _ in indexes:
            cursor.execute(f"PRAGMA index_info({_quote_identifier(name)})")
            columns = [row[2] for row in cursor.fetchall()]
            if columns and columns[0] in {"source", "target"}:
                usable_names.append(name)

        assert usable_names, (
            "The deps index must have source or target as its leading column so it can support a dependency join."
        )

        # Do not allow SQLite to hide an irrelevant submitted index by creating
        # a transient automatic index for this verification connection.
        cursor.execute("PRAGMA automatic_index=OFF")
        cursor.execute("EXPLAIN QUERY PLAN " + QUERY)
        plan = [row[3] for row in cursor.fetchall()]
        deps_searches = [detail for detail in plan if "search d" in detail.lower()]

        assert deps_searches, "The optimized query plan still does not perform an indexed SEARCH of deps. Plan: " + repr(plan)
        assert any(
            index_name.lower() in detail.lower()
            for detail in deps_searches
            for index_name in usable_names
        ), "The query plan does not use the submitted relevant deps index. Plan: " + repr(plan)
    finally:
        conn.close()


def _expected_critical_jobs():
    conn = sqlite3.connect(DB_PATH)
    try:
        edges = conn.execute(QUERY).fetchall()
    finally:
        conn.close()

    assert edges, "The optimized SQL projection returned no dependency edges"

    graph = nx.DiGraph()
    graph.add_edges_from(edges)
    scores = nx.pagerank(graph, alpha=0.85, max_iter=100)
    assert len(scores) >= 5, "The projected graph contains fewer than five nodes"

    return [
        job_id
        for job_id, _ in sorted(scores.items(), key=lambda item: item[1], reverse=True)[:5]
    ]


def test_microservice_critical_keys():
    """Recompute PageRank from the SQL projection and verify the service result."""
    expected_jobs = _expected_critical_jobs()

    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the microservice at {URL}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")

    assert isinstance(data, dict), "Expected JSON response to be a dictionary"
    assert set(data.keys()) == set(expected_jobs), f"Expected keys {expected_jobs}, but got {list(data.keys())}"

    for job_id in expected_jobs:
        try:
            output = subprocess.check_output([KEY_DERIVER_PATH, job_id], text=True).strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Failed to execute key_deriver for {job_id}: {e}")

        assert data[job_id] == output, f"Incorrect key for {job_id}. Expected {output}, got {data[job_id]}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
