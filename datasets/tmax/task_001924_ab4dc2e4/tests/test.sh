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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import secrets
import sqlite3
import string

import pytest
import requests

DB_PATH = "/home/user/backup.db"
SQL_PATH = "/home/user/extract_graph.sql"
URL = "http://127.0.0.1:8080/validate"


@pytest.fixture(scope="session", autouse=True)
def dynamic_backup():
    """Add an unpredictable backup after the agent's service has been started."""
    rng = random.SystemRandom()
    conn = sqlite3.connect(DB_PATH, timeout=10)
    try:
        while True:
            backup_id = secrets.randbelow(1_000_000_000) + 1000
            if conn.execute(
                "SELECT 1 FROM nodes WHERE backup_id = ? UNION SELECT 1 FROM edges WHERE backup_id = ? LIMIT 1",
                (backup_id, backup_id),
            ).fetchone() is None:
                break

        def label():
            return "dyn_" + "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(14))

        labels = []
        while len(labels) < 9:
            candidate = label()
            if candidate not in labels:
                labels.append(candidate)

        rng.shuffle(labels)
        center = labels[0]
        # An acyclic graph gives an unambiguous clustering coefficient of zero,
        # while the randomized degree-four center exercises extraction and ranking.
        pairs = [
            (center, labels[1]),
            (center, labels[2]),
            (center, labels[3]),
            (center, labels[4]),
            (labels[1], labels[5]),
            (labels[2], labels[6]),
        ]
        edges = []
        for source, target in pairs:
            if rng.choice((True, False)):
                source, target = target, source
            edges.append((source, target))

        conn.executemany(
            "INSERT INTO nodes(id, backup_id) VALUES (?, ?)",
            [(node, backup_id) for node in labels],
        )
        conn.executemany(
            "INSERT INTO edges(source_id, target_id, backup_id) VALUES (?, ?, ?)",
            [(source, target, backup_id) for source, target in edges],
        )
        conn.commit()
        yield {
            "backup_id": backup_id,
            "labels": labels,
            "edges": edges,
            "center": center,
        }
    finally:
        conn.close()


def post_validate(backup_id):
    try:
        response = requests.post(URL, json={"backup_id": backup_id}, timeout=5)
        response.raise_for_status()
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to or get valid response from API: {exc}")
    try:
        return response.json()
    except ValueError as exc:
        pytest.fail(f"API response was not valid JSON: {exc}")


def test_api_backup_1():
    data = post_validate(1)
    assert data.get("backup_id") == 1, f"Expected backup_id 1, got {data.get('backup_id')}"
    assert data.get("top_centrality_node") == "A", f"Expected top_centrality_node 'A', got {data.get('top_centrality_node')}"

    avg_clustering = data.get("avg_clustering")
    assert avg_clustering is not None, "avg_clustering is missing in response"
    assert math.isclose(avg_clustering, 0.3333, rel_tol=1e-3), f"Expected avg_clustering ~0.3333, got {avg_clustering}"


def test_api_backup_2():
    data = post_validate(2)
    assert data.get("backup_id") == 2, f"Expected backup_id 2, got {data.get('backup_id')}"
    assert data.get("top_centrality_node") == "X", f"Expected top_centrality_node 'X', got {data.get('top_centrality_node')}"

    avg_clustering = data.get("avg_clustering")
    assert avg_clustering is not None, "avg_clustering is missing in response"
    assert math.isclose(avg_clustering, 0.0, rel_tol=1e-3), f"Expected avg_clustering 0.0, got {avg_clustering}"


def test_api_unpredictable_backup(dynamic_backup):
    data = post_validate(dynamic_backup["backup_id"])
    assert set(data) == {"backup_id", "top_centrality_node", "avg_clustering"}
    assert data["backup_id"] == dynamic_backup["backup_id"]
    assert data["top_centrality_node"] == dynamic_backup["center"]
    assert isinstance(data["avg_clustering"], (int, float)) and not isinstance(data["avg_clustering"], bool)
    assert math.isclose(float(data["avg_clustering"]), 0.0, abs_tol=0.00005)


def test_database_indexes():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    def has_index_on_column(table_name, column_name):
        cursor.execute(f"PRAGMA index_list('{table_name}')")
        indexes = cursor.fetchall()
        for idx in indexes:
            index_name = idx[1]
            cursor.execute(f"PRAGMA index_info('{index_name}')")
            cols = cursor.fetchall()
            if any(col[2] == column_name for col in cols):
                return True
        return False

    assert has_index_on_column('nodes', 'backup_id'), "Missing index on 'backup_id' in 'nodes' table."
    assert has_index_on_column('edges', 'backup_id'), "Missing index on 'backup_id' in 'edges' table."
    conn.close()


def execute_parameterized(conn, sql, value):
    names = set(re.findall(r"(?<!:)[\:@$]([A-Za-z_][A-Za-z0-9_]*|[0-9]+)", sql))
    numbered = [int(n) for n in re.findall(r"\?([0-9]+)", sql)]
    plain_count = len(re.findall(r"\?(?![0-9])", sql))

    candidates = []
    if names:
        candidates.append({name: value for name in names})
    if numbered:
        candidates.append(tuple(value for _ in range(max(numbered))))
    if plain_count:
        candidates.append(tuple(value for _ in range(plain_count)))

    assert candidates, "The extraction query has no executable SQLite parameter binding."
    errors = []
    for params in candidates:
        try:
            cursor = conn.execute(sql, params)
            return cursor.fetchall()
        except sqlite3.Error as exc:
            errors.append(str(exc))
    pytest.fail("The extraction query could not be executed with its parameter: " + " | ".join(errors))


def test_extract_graph_sql_fixed_and_executable(dynamic_backup):
    assert os.path.exists(SQL_PATH), f"SQL script {SQL_PATH} is missing."
    with open(SQL_PATH, "r", encoding="utf-8") as handle:
        content = handle.read()

    # Preserve the original parameterization and implicit-cross-join assertions.
    parameterized = any(char in content for char in ['?', '$', ':', '@'])
    assert parameterized, f"The query in {SQL_PATH} does not appear to be parameterized."
    lower_content = content.lower()
    assert "nodes n1, nodes n2" not in lower_content, "The query still contains the implicit cross join 'nodes n1, nodes n2'."

    conn = sqlite3.connect(DB_PATH)
    try:
        rows = execute_parameterized(conn, content, dynamic_backup["backup_id"])
        assert all(len(row) == 2 for row in rows), "Extraction query must return source and target columns."
        assert sorted(tuple(row) for row in rows) == sorted(dynamic_backup["edges"]), \
            "Extraction query did not return exactly the edges belonging to the requested backup."

        absent_id = dynamic_backup["backup_id"] + 1
        while conn.execute(
            "SELECT 1 FROM nodes WHERE backup_id=? UNION SELECT 1 FROM edges WHERE backup_id=? LIMIT 1",
            (absent_id, absent_id),
        ).fetchone() is not None:
            absent_id += 1
        assert execute_parameterized(conn, content, absent_id) == [], \
            "Extraction query is not actually constrained by its backup_id parameter."
    finally:
        conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
