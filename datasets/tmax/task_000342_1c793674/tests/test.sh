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
import secrets
import sqlite3
import requests
import pytest

DB_PATH = "/app/graph.db"
URL = "http://127.0.0.1:9000/analyze"


def post_analyze(node_id):
    try:
        response = requests.post(URL, json={"node_id": node_id}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {URL}: {e}")

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response: {response.text}"
    )

    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response: {response.text}")


def expected_results(conn, node_id):
    edges = set(conn.execute("SELECT src, dst FROM edges").fetchall())
    first_hop = {dst for src, dst in edges if src == node_id}
    second_hop = {dst for src, dst in edges if src in first_hop}

    results = []
    for neighbor in second_hop:
        in_degree = len({src for src, dst in edges if dst == neighbor})
        results.append({"id": neighbor, "in_degree": in_degree})

    return sorted(results, key=lambda row: (-row["in_degree"], row["id"]))


def test_database_deduplicated():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT src, dst, COUNT(*) FROM edges GROUP BY src, dst HAVING COUNT(*) > 1")
    duplicates = cursor.fetchall()
    conn.close()

    assert len(duplicates) == 0, f"The edges table still contains duplicate records: {duplicates}"


def test_analyze_endpoint_node_1():
    data = post_analyze(1)

    expected = [
        {"id": 5, "in_degree": 3},
        {"id": 4, "in_degree": 1},
        {"id": 6, "in_degree": 1}
    ]

    assert "results" in data, "Response JSON is missing the 'results' key."
    assert data["results"] == expected, f"Expected results {expected}, but got {data['results']}"


def test_analyze_endpoint_dynamic_graph():
    conn = sqlite3.connect(DB_PATH, timeout=5)
    probe_nodes = []

    try:
        existing = {row[0] for row in conn.execute("SELECT id FROM nodes")}
        while True:
            base = 100000000 + secrets.randbelow(1000000000)
            candidate = list(range(base, base + 9))
            if not existing.intersection(candidate):
                probe_nodes = candidate
                break

        root, a, b, c, d, e, x, y, z = probe_nodes
        conn.executemany("INSERT INTO nodes(id) VALUES (?)", [(n,) for n in probe_nodes])
        conn.executemany(
            "INSERT INTO edges(src, dst) VALUES (?, ?)",
            [
                (root, a), (root, b),
                (a, c), (a, d),
                (b, c), (b, e),
                (x, c),
                (y, e), (z, e),
            ],
        )
        conn.commit()

        expected = expected_results(conn, root)
        data = post_analyze(root)

        assert "results" in data, "Response JSON is missing the 'results' key."
        assert data["results"] == expected, (
            f"For dynamic node_id {root}, expected results {expected}, "
            f"but got {data['results']}"
        )
    finally:
        if probe_nodes:
            placeholders = ",".join("?" for _ in probe_nodes)
            conn.execute(
                f"DELETE FROM edges WHERE src IN ({placeholders}) OR dst IN ({placeholders})",
                probe_nodes + probe_nodes,
            )
            conn.execute(f"DELETE FROM nodes WHERE id IN ({placeholders})", probe_nodes)
            conn.commit()
        conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
