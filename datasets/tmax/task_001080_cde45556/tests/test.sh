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
import json
import os
import sqlite3
import uuid
from collections import Counter
from heapq import heappop, heappush

import cv2
import pytest
import requests

DB_PATH = "/home/user/graph.db"
VIDEO_PATH = "/app/dataset_transmission.mp4"
API_URL = "http://127.0.0.1:8080/shortest_path"
AUTH_HEADER = {"Authorization": "Bearer RESEARCH_TOKEN_99"}


def decode_video():
    capture = cv2.VideoCapture(VIDEO_PATH)
    assert capture.isOpened(), f"Could not open {VIDEO_PATH}"
    bits = []
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        bits.append("1" if float(gray.mean()) > 128 else "0")
    capture.release()

    assert bits, "Video contained no decodable frames"
    assert len(bits) % 8 == 0, "Video bit count is not byte-aligned"
    raw = bytes(int("".join(bits[i:i + 8]), 2) for i in range(0, len(bits), 8))
    data = json.loads(raw.decode("ascii"))
    assert isinstance(data, list) and data, "Decoded dataset is not a nonempty JSON array"
    for edge in data:
        assert set(edge) == {"source", "target", "weight"}
        assert isinstance(edge["source"], str) and isinstance(edge["target"], str)
        assert isinstance(edge["weight"], (int, float)) and edge["weight"] > 0
    return data


EXPECTED_EDGES = decode_video()
EXPECTED_COUNTER = Counter(
    (e["source"], e["target"], e["weight"]) for e in EXPECTED_EDGES
)
NODES = sorted({e["source"] for e in EXPECTED_EDGES} | {e["target"] for e in EXPECTED_EDGES})
EDGE_COST = {}
for edge in EXPECTED_EDGES:
    key = (edge["source"], edge["target"])
    EDGE_COST[key] = min(EDGE_COST.get(key, edge["weight"]), edge["weight"])


def qi(name):
    return '"' + name.replace('"', '""') + '"'


def table_columns(conn, table):
    return [row[1] for row in conn.execute(f"PRAGMA table_info({qi(table)})")]


def locate_edge_storage(conn):
    tables = [row[0] for row in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    )]
    source_names = ("source", "source_id", "source_node_id")
    target_names = ("target", "target_id", "target_node_id")

    for table in tables:
        columns = table_columns(conn, table)
        lower = {column.lower(): column for column in columns}
        source = next((lower[n] for n in source_names if n in lower), None)
        target = next((lower[n] for n in target_names if n in lower), None)
        weight = lower.get("weight")
        if not (source and target and weight):
            continue

        rows = conn.execute(
            f"SELECT {qi(source)}, {qi(target)}, {qi(weight)} FROM {qi(table)}"
        ).fetchall()
        if Counter(rows) == EXPECTED_COUNTER:
            return table, source, target, weight, rows

        # Also accept a conventional normalized schema where edge endpoints are
        # foreign keys into a node table.
        for node_table in tables:
            node_columns = table_columns(conn, node_table)
            node_lower = {column.lower(): column for column in node_columns}
            id_column = next((node_lower[n] for n in ("id", "node_id") if n in node_lower), None)
            label_column = next((node_lower[n] for n in ("name", "label", "value", "node", "node_name") if n in node_lower), None)
            if not id_column or not label_column:
                continue
            mapping = dict(conn.execute(
                f"SELECT {qi(id_column)}, {qi(label_column)} FROM {qi(node_table)}"
            ).fetchall())
            try:
                resolved = [(mapping[s], mapping[t], w) for s, t, w in rows]
            except (KeyError, TypeError):
                continue
            if Counter(resolved) == EXPECTED_COUNTER:
                return table, source, target, weight, rows

    pytest.fail("Could not find a relational edge table containing exactly the video dataset")


def shortest_distance(start, end):
    if start == end:
        return 0
    adjacency = {}
    for (source, target), weight in EDGE_COST.items():
        adjacency.setdefault(source, []).append((target, weight))
    queue = [(0, start)]
    distances = {start: 0}
    while queue:
        distance, node = heappop(queue)
        if distance != distances[node]:
            continue
        if node == end:
            return distance
        for target, weight in adjacency.get(node, []):
            candidate = distance + weight
            if candidate < distances.get(target, float("inf")):
                distances[target] = candidate
                heappush(queue, (candidate, target))
    return None


def authenticated_request(start, end):
    try:
        return requests.post(
            API_URL,
            json={"start": start, "end": end},
            headers=AUTH_HEADER,
            timeout=5,
        )
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to API: {exc}")


def test_database_exists():
    """Original database existence and validity assertions."""
    assert os.path.exists(DB_PATH), f"Database file not found at {DB_PATH}"
    assert os.path.isfile(DB_PATH), f"Path {DB_PATH} is not a file"
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = cursor.fetchall()
        assert len(tables) > 0, "Database exists but contains no tables"
        assert conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
        conn.close()
    except sqlite3.Error as exc:
        pytest.fail(f"Failed to connect to SQLite database: {exc}")


def test_database_contains_video_edges_and_positive_weight_constraint():
    conn = sqlite3.connect(DB_PATH)
    try:
        table, source, target, weight, rows = locate_edge_storage(conn)
        assert len(rows) == len(EXPECTED_EDGES)

        # A database-level constraint or trigger must reject a nonpositive weight.
        sample_source, sample_target, sample_weight = rows[0]
        conn.execute("SAVEPOINT constraint_test")
        rejected = False
        try:
            cursor = conn.execute(
                f"UPDATE {qi(table)} SET {qi(weight)} = 0 "
                f"WHERE {qi(source)} = ? AND {qi(target)} = ? AND {qi(weight)} = ?",
                (sample_source, sample_target, sample_weight),
            )
            assert cursor.rowcount > 0, "Could not exercise the stored edge constraint"
        except sqlite3.IntegrityError:
            rejected = True
        finally:
            conn.execute("ROLLBACK TO constraint_test")
            conn.execute("RELEASE constraint_test")
        assert rejected, "The edge table does not enforce that weights are positive"
    finally:
        conn.close()


def test_api_missing_auth():
    try:
        response = requests.post(API_URL, json={"start": "A", "end": "E"}, timeout=5)
        assert response.status_code == 401, f"Expected status code 401 for missing auth, got {response.status_code}"
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to API: {exc}")


def test_api_invalid_auth():
    try:
        headers = {"Authorization": "Bearer WRONG_TOKEN"}
        response = requests.post(API_URL, json={"start": "A", "end": "E"}, headers=headers, timeout=5)
        assert response.status_code == 401, f"Expected status code 401 for invalid auth, got {response.status_code}"
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to API: {exc}")


def test_api_shortest_path_a_e():
    response = authenticated_request("A", "E")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "path" in data, "Response JSON missing 'path' key"
    assert "cost" in data, "Response JSON missing 'cost' key"
    assert data["path"] == ["A", "C", "D", "E"], f"Expected path ['A', 'C', 'D', 'E'], got {data['path']}"
    assert data["cost"] == 9, f"Expected cost 9, got {data['cost']}"


def test_api_shortest_path_b_f():
    response = authenticated_request("B", "F")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert data["path"] == ["B", "C", "F"], f"Expected path ['B', 'C', 'F'], got {data.get('path')}"
    assert data["cost"] == 12, f"Expected cost 12, got {data.get('cost')}"


def test_api_path_not_found():
    response = authenticated_request("A", "Z")
    assert response.status_code == 404, f"Expected status code 404 for non-existent path, got {response.status_code}"


def test_api_all_video_node_pairs():
    """Exercise every pair, deriving shortest costs from the decoded video."""
    for start in NODES:
        for end in NODES:
            expected = shortest_distance(start, end)
            response = authenticated_request(start, end)
            if expected is None:
                assert response.status_code == 404, (
                    f"Expected no path from {start} to {end}, got {response.status_code}: {response.text}"
                )
                continue

            assert response.status_code == 200, (
                f"Expected a path from {start} to {end}, got {response.status_code}: {response.text}"
            )
            data = response.json()
            assert set(data) == {"path", "cost"}, f"Response does not precisely match the required schema: {data}"
            path = data["path"]
            cost = data["cost"]
            assert isinstance(path, list) and path, f"Invalid path for {start} to {end}: {path}"
            assert path[0] == start and path[-1] == end
            assert len(path) == len(set(path)), f"Returned path contains a cycle: {path}"
            actual_cost = 0
            for source, target in zip(path, path[1:]):
                assert (source, target) in EDGE_COST, f"Returned path uses nonexistent edge {source}->{target}"
                actual_cost += EDGE_COST[(source, target)]
            assert cost == actual_cost, f"Reported cost {cost} does not equal path cost {actual_cost}"
            assert cost == expected, f"Path from {start} to {end} is not shortest: expected {expected}, got {cost}"


def test_api_random_unknown_nodes_and_sql_metacharacters():
    marker = "UNKNOWN_'_" + uuid.uuid4().hex
    for start, end in ((marker, "A"), ("A", marker), (marker, marker + "_2")):
        response = authenticated_request(start, end)
        assert response.status_code == 404, (
            f"Expected 404 for unknown node query {start!r}->{end!r}, got {response.status_code}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
