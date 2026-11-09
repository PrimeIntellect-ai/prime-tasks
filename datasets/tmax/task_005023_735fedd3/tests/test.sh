#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import sqlite3
import subprocess
from collections import Counter

import pytest
import requests

DB_PATH = "/app/graph.db"
API_URL = "http://127.0.0.1:8080/api/two-hop"
AUTH = {"Authorization": "Bearer graph-admin-token"}


def subtitle_edges():
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", "/app/network_topology.mp4", "-map", "0:s:0", "-f", "srt", "-"],
        check=True,
        capture_output=True,
        text=True,
    )
    edges = []
    for line in result.stdout.splitlines():
        match = re.fullmatch(r"([^,\r\n]+),([^,\r\n]+),(-?\d+)", line.strip())
        if match:
            edges.append((match.group(1), match.group(2), int(match.group(3))))
    assert edges, "No graph edges could be extracted from the subtitle stream."
    return edges


def test_database_exists_and_indexed():
    """Check that the SQLite database exists, has the correct table, indexes, and data."""
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='edges'")
    assert cursor.fetchone() is not None, "Table 'edges' does not exist in graph.db."

    cursor.execute("PRAGMA table_info(edges)")
    columns = {row[1]: (row[2] or "").upper() for row in cursor.fetchall()}
    assert columns.get("source") == "TEXT", "edges.source must be a TEXT column."
    assert columns.get("target") == "TEXT", "edges.target must be a TEXT column."
    assert columns.get("weight") == "INTEGER", "edges.weight must be an INTEGER column."

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='edges'")
    indexes = cursor.fetchall()
    assert len(indexes) > 0, "No indexes found on the 'edges' table. Query optimization was not implemented."

    leading_index_columns = set()
    for (name,) in indexes:
        escaped = name.replace('"', '""')
        cursor.execute(f'PRAGMA index_info("{escaped}")')
        indexed_columns = [row[2] for row in cursor.fetchall()]
        if indexed_columns:
            leading_index_columns.add(indexed_columns[0])
    assert "source" in leading_index_columns, "No index efficiently supports filtering edges by source."
    assert "target" in leading_index_columns, "No index efficiently supports filtering edges by target."

    cursor.execute("SELECT COUNT(*) FROM edges")
    count = cursor.fetchone()[0]
    assert count >= 5, f"The edges table only contains {count} rows. Expected at least 5 rows from the extracted subtitle data."

    cursor.execute("SELECT source, target, weight FROM edges")
    actual = Counter(cursor.fetchall())
    expected = Counter(subtitle_edges())
    assert actual == expected, f"edges does not exactly contain the subtitle graph data. Expected {expected}, got {actual}."
    conn.close()


def test_http_api_unauthorized():
    """Check that the API rejects requests without the exact authorization header."""
    try:
        response = requests.get(API_URL, params={"start": "A", "end": "D"}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Go service on port 8080: {e}")
    assert response.status_code == 401, f"Expected HTTP 401 Unauthorized for missing auth header, got {response.status_code}."

    response = requests.get(
        API_URL,
        params={"start": "A", "end": "D"},
        headers={"Authorization": "Bearer wrong-token"},
        timeout=5,
    )
    assert response.status_code == 401, f"Expected HTTP 401 for an incorrect auth token, got {response.status_code}."


def test_http_api_authorized_and_correct_logic():
    """Retain the known graph query check, including exact ordering and JSON shape."""
    try:
        response = requests.get(API_URL, params={"start": "A", "end": "D"}, headers=AUTH, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Go service on port 8080: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    expected = [
        {"path": "A->C->D", "total_weight": 11},
        {"path": "A->B->D", "total_weight": 15},
    ]
    assert data == expected, f"API returned incorrect data.\nExpected: {expected}\nGot: {data}"


def test_http_api_queries_live_database_with_parameterized_join():
    """Exercise unpredictable graph data so fixed responses and the old cross join cannot pass."""
    token = secrets.token_hex(8)
    start = f"S_{token}'q"
    end = f"E_{token}"
    middle1 = f"M1_{token}"
    middle2 = f"M2_{token}"
    dead = f"DEAD_{token}"
    orphan = f"ORPHAN_{token}"

    w1, w2, w3, w4 = [secrets.randbelow(30) + 1 for _ in range(4)]
    if w1 + w2 == w3 + w4:
        w4 += 1

    inserted = [
        (start, middle1, w1),
        (middle1, end, w2),
        (start, middle2, w3),
        (middle2, end, w4),
        # These rows produce false results under the legacy implicit cross join.
        (start, dead, 101),
        (orphan, end, 103),
        (middle1, dead, 107),
    ]

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executemany("INSERT INTO edges(source, target, weight) VALUES (?, ?, ?)", inserted)
        conn.commit()
        rows = conn.execute(
            """
            SELECT e1.source, e1.target, e2.target, e1.weight + e2.weight AS total_weight
            FROM edges AS e1
            JOIN edges AS e2 ON e1.target = e2.source
            WHERE e1.source = ? AND e2.target = ?
            ORDER BY total_weight ASC
            """,
            (start, end),
        ).fetchall()
        expected = [
            {"path": f"{source}->{middle}->{target}", "total_weight": total}
            for source, middle, target, total in rows
        ]
        assert len(expected) == 2
    finally:
        conn.close()

    try:
        response = requests.get(API_URL, params={"start": start, "end": end}, headers=AUTH, timeout=5)
        assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
        assert data == expected, f"API did not execute the correct live two-hop join. Expected {expected}, got {data}."

        empty_response = requests.get(API_URL, params={"start": end, "end": start}, headers=AUTH, timeout=5)
        assert empty_response.status_code == 200
        assert empty_response.json() == [], "A query with no valid two-hop paths must return an empty JSON array."
    finally:
        cleanup = sqlite3.connect(DB_PATH)
        try:
            names = (start, end, middle1, middle2, dead, orphan)
            placeholders = ",".join("?" for _ in names)
            cleanup.execute(
                f"DELETE FROM edges WHERE source IN ({placeholders}) OR target IN ({placeholders})",
                names + names,
            )
            cleanup.commit()
        finally:
            cleanup.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
