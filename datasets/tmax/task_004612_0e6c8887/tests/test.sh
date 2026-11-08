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
import sqlite3
import time
from collections import deque

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
DB_PATH = "/home/user/audit_records.db"
EXPECTED_DEPTH = 2


def wait_for_service(url, timeout=5):
    """Wait for the service to become available."""
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            response = requests.get(url, timeout=1)
            if response.status_code == 200 or response.status_code == 404:
                return True
        except requests.exceptions.RequestException:
            time.sleep(0.5)
    return False


def load_graph():
    """Derive the undirected graph directly from the supplied SQLite database."""
    conn = sqlite3.connect(DB_PATH)
    try:
        nodes = dict(conn.execute("SELECT node_id, entity_name FROM nodes").fetchall())
        adjacency = {node_id: set() for node_id in nodes}
        for source_id, target_id in conn.execute("SELECT source_id, target_id FROM edges"):
            adjacency[source_id].add(target_id)
            adjacency[target_id].add(source_id)
        return nodes, adjacency
    finally:
        conn.close()


def expected_trace(start_name, depth):
    nodes, adjacency = load_graph()
    ids_by_name = {name: node_id for node_id, name in nodes.items()}
    start_id = ids_by_name[start_name]
    seen = {start_id}
    queue = deque([(start_id, 0)])

    while queue:
        node_id, distance = queue.popleft()
        if distance == depth:
            continue
        for neighbor in adjacency[node_id]:
            if neighbor not in seen:
                seen.add(neighbor)
                queue.append((neighbor, distance + 1))

    return sorted(nodes[node_id] for node_id in seen)


def request_trace(entity):
    try:
        response = requests.get(
            f"{BASE_URL}/api/trace", params={"entity": entity}, timeout=5
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to query trace for {entity!r}: {exc}")

    assert response.status_code == 200, (
        f"Expected status code 200 for entity {entity!r}, got {response.status_code}."
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(
            f"Trace response for {entity!r} is not valid JSON: {response.text}"
        )

    assert isinstance(data, list), f"Expected JSON array, got {type(data).__name__}"
    assert all(isinstance(item, str) for item in data), "Trace entries must be strings."
    assert data == sorted(list(set(data))), (
        "Returned array is not sorted alphabetically or contains duplicates."
    )
    return data


def test_alert_info_endpoint():
    """Test the /api/alert_info endpoint returns the correct target and depth."""
    endpoint = f"{BASE_URL}/api/alert_info"

    assert wait_for_service(BASE_URL), f"Service at {BASE_URL} is not reachable."

    try:
        response = requests.get(endpoint, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {endpoint}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}."

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert "target" in data, "Key 'target' missing in JSON response."
    assert "depth" in data, "Key 'depth' missing in JSON response."

    assert data["target"] == "BlackOasis", f"Expected target 'BlackOasis', got '{data['target']}'"
    assert data["depth"] == 2, f"Expected depth 2, got {data['depth']}"


def test_trace_endpoint():
    """Retain the original BlackOasis traversal assertion."""
    endpoint = f"{BASE_URL}/api/trace?entity=BlackOasis"

    assert wait_for_service(BASE_URL), f"Service at {BASE_URL} is not reachable."

    try:
        response = requests.get(endpoint, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {endpoint}: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}."

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert isinstance(data, list), f"Expected JSON array, got {type(data).__name__}"

    expected_entities = ["BlackOasis", "Crimson_Shell", "Frontier_Corp", "Global_Holdings", "Shadow_Trust"]

    assert data == sorted(list(set(data))), "Returned array is not sorted alphabetically or contains duplicates."
    assert data == expected_entities, f"Expected {expected_entities}, got {data}"


def test_trace_from_every_database_entity():
    """Exercise traversal from every entity using expectations derived from SQLite."""
    assert wait_for_service(BASE_URL), f"Service at {BASE_URL} is not reachable."
    nodes, _ = load_graph()
    entity_names = sorted(nodes.values())
    assert entity_names, "No entities found in the audit database."

    for entity in entity_names:
        actual = request_trace(entity)
        expected = expected_trace(entity, EXPECTED_DEPTH)
        assert actual == expected, (
            f"Incorrect depth-{EXPECTED_DEPTH} traversal for {entity!r}: "
            f"expected {expected}, got {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
