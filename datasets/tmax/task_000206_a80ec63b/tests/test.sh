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
import csv
import importlib.util
import secrets
import sys
import time
from collections import Counter, defaultdict, deque

import pytest
import requests

NODES_PATH = "/data/nodes.csv"
EDGES_PATH = "/data/edges.csv"
ENGINE_PATH = "/app/simple_graph/engine.py"
BASE_URL = "http://127.0.0.1:8080/shortest_path"


def load_graph():
    with open(NODES_PATH, newline="") as f:
        nodes = [row["id"] for row in csv.DictReader(f)]

    adjacency = defaultdict(list)
    edge_set = set()
    with open(EDGES_PATH, newline="") as f:
        for row in csv.DictReader(f):
            src = row["source_id"]
            dst = row["target_id"]
            adjacency[src].append(dst)
            edge_set.add((src, dst))
    return nodes, adjacency, edge_set


NODES, ADJACENCY, EDGE_SET = load_graph()


def shortest_distance(src, dst):
    queue = deque([(src, 0)])
    visited = {src}
    while queue:
        node, distance = queue.popleft()
        if node == dst:
            return distance
        for neighbor in ADJACENCY.get(node, []):
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append((neighbor, distance + 1))
    return None


def request_path(src, dst):
    start = time.time()
    try:
        response = requests.get(
            BASE_URL, params={"src": src, "dst": dst}, timeout=2.0
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server or request timed out: {e}")
    duration = time.time() - start

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Server did not return valid JSON.")
    assert "path" in data, "JSON response missing 'path' key."
    return data["path"], duration


def assert_valid_shortest_path(src, dst, path):
    expected_distance = shortest_distance(src, dst)
    if expected_distance is None:
        assert path is None, f"Expected no path from {src} to {dst}, got {path}"
        return

    assert isinstance(path, list), "'path' must be a list."
    assert path, "Reachable query returned an empty path."
    assert path[0] == src, f"Expected path to start with {src}, but got {path[0]}"
    assert path[-1] == dst, f"Expected path to end with {dst}, but got {path[-1]}"
    for left, right in zip(path, path[1:]):
        assert (left, right) in EDGE_SET, f"Non-edge used in path: {left} -> {right}"
    assert len(path) - 1 == expected_distance, (
        f"Path from {src} to {dst} is not shortest: got {len(path) - 1} edges, "
        f"expected {expected_distance}"
    )


def test_server_running_and_fast():
    path, duration = request_path("1", "50")

    assert isinstance(path, list), "'path' must be a list."
    assert len(path) >= 2, "Path must contain at least the source and destination."
    assert path[0] == "1", f"Expected path to start with '1', but got {path[0]}"
    assert path[-1] == "50", f"Expected path to end with '50', but got {path[-1]}"
    assert duration < 2.0, (
        f"Request took too long ({duration:.2f}s). The missing index or cross join bug might not be fixed."
    )
    assert_valid_shortest_path("1", "50", path)


def test_server_on_unpredictable_graph_queries():
    rng = secrets.SystemRandom()
    pairs = set()
    while len(pairs) < 12:
        src = rng.choice(NODES)
        dst = rng.choice(NODES)
        if src != dst:
            pairs.add((src, dst))

    for src, dst in pairs:
        path, duration = request_path(src, dst)
        assert duration < 2.0, f"Query {src}->{dst} took too long ({duration:.2f}s)"
        assert_valid_shortest_path(src, dst, path)


def load_engine_module():
    spec = importlib.util.spec_from_file_location("submitted_graph_engine", ENGINE_PATH)
    assert spec is not None and spec.loader is not None, "Could not load engine.py"
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def test_engine_runtime_neighbors_and_index():
    module = load_engine_module()
    engine = module.GraphEngine(NODES_PATH, EDGES_PATH)

    rng = secrets.SystemRandom()
    sampled_nodes = set(rng.sample(NODES, min(25, len(NODES))))
    sampled_nodes.update(["1", "10", "20", "30", "40", "50"])
    for node_id in sampled_nodes:
        actual = engine.get_neighbors(node_id)
        expected = ADJACENCY.get(node_id, [])
        assert Counter(actual) == Counter(expected), (
            f"get_neighbors({node_id!r}) did not return exactly its direct targets"
        )

    indexes = engine.conn.execute("PRAGMA index_list('edges')").fetchall()
    assert indexes, "The edges table has no index"
    source_index_found = False
    for index_row in indexes:
        index_name = index_row[1]
        columns = engine.conn.execute(
            'PRAGMA index_info("' + index_name.replace('"', '""') + '")'
        ).fetchall()
        if columns and columns[0][2] == "source_id":
            source_index_found = True
            break
    assert source_index_found, "Missing an index whose leading column is edges.source_id"


def test_engine_code_fixed():
    with open(ENGINE_PATH, "r") as f:
        content = f.read()

    # Preserve the original source assertions in addition to runtime verification.
    assert "CREATE INDEX" in content.upper(), "Missing index creation in engine.py"
    assert "FROM edges e, nodes n" not in content, "Implicit cross join still present in engine.py"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
