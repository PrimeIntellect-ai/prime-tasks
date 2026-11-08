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
import ast
import importlib.util
import os
import re
import sqlite3
import uuid

import flask
import pytest
import requests

BASE_URL = "http://127.0.0.1:8000"
AUTH_HEADER = {"Authorization": "Bearer db-admin-token"}
API_PATH = "/home/user/api.py"
DB_PATH = "/app/network.db"


def assert_exact_payload(data, expected_nodes):
    assert isinstance(data, dict), f"Expected a JSON object, got {type(data).__name__}"
    assert set(data.keys()) == {"infected_nodes"}, f"Response must contain exactly the infected_nodes key, got {set(data.keys())}"
    assert isinstance(data["infected_nodes"], list), "infected_nodes must be a JSON list"
    actual_nodes = set(data["infected_nodes"])
    assert actual_nodes == expected_nodes, f"Expected nodes {expected_nodes}, got {actual_nodes}"
    assert len(data["infected_nodes"]) == len(actual_nodes), "Response contains duplicated nodes, deduplication failed"


def closure_from_database(start_node):
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("SELECT parent_id, child_id FROM edges").fetchall()
    finally:
        conn.close()

    adjacency = {}
    for parent, child in rows:
        adjacency.setdefault(parent, []).append(child)

    seen = {start_node}
    pending = [start_node]
    while pending:
        current = pending.pop()
        for child in adjacency.get(current, []):
            if child not in seen:
                seen.add(child)
                pending.append(child)
    return seen


@pytest.fixture(scope="session", autouse=True)
def randomized_graph():
    token = uuid.uuid4().hex
    root = f"DYN_{token}' OR '1'='1"
    left = f"DYN_{token}_LEFT"
    right = f"DYN_{token}_RIGHT"
    shared = f"DYN_{token}_SHARED"
    leaf = f"DYN_{token}_LEAF"
    rows = [
        (root, left),
        (root, right),
        (left, shared),
        (right, shared),
        (shared, leaf),
    ]

    conn = sqlite3.connect(DB_PATH, timeout=10)
    try:
        conn.executemany("INSERT INTO edges(parent_id, child_id) VALUES (?, ?)", rows)
        conn.commit()
    finally:
        conn.close()

    yield {"root": root, "left": left, "shared": shared, "leaf": leaf, "rows": rows}

    conn = sqlite3.connect(DB_PATH, timeout=10)
    try:
        conn.executemany("DELETE FROM edges WHERE parent_id = ? AND child_id = ?", rows)
        conn.commit()
    finally:
        conn.close()


@pytest.fixture(scope="session")
def submitted_app():
    assert os.path.isfile(API_PATH), f"Required API script does not exist: {API_PATH}"

    original_run = flask.Flask.run
    flask.Flask.run = lambda self, *args, **kwargs: None
    try:
        spec = importlib.util.spec_from_file_location("submitted_api", API_PATH)
        assert spec is not None and spec.loader is not None, "Could not load /home/user/api.py"
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
    finally:
        flask.Flask.run = original_run

    assert hasattr(module, "app"), "/home/user/api.py must define a Flask app"
    assert isinstance(module.app, flask.Flask), "The app object must be a Flask application"
    return module.app


def test_api_source_uses_recursive_parameterized_sqlite_query():
    assert os.path.isfile(API_PATH), f"Required API script does not exist: {API_PATH}"
    with open(API_PATH, "r", encoding="utf-8") as handle:
        source = handle.read()

    ast.parse(source)
    lowered = source.lower()
    assert "sqlite3" in lowered, "API must use SQLite"
    assert DB_PATH in source, "API must query /app/network.db"
    assert re.search(r"with\s+recursive", source, re.IGNORECASE), "API must use a recursive CTE"

    tree = ast.parse(source)
    parameterized_executes = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if node.func.attr in {"execute", "executemany"} and len(node.args) >= 2:
                parameterized_executes.append(node)
    assert parameterized_executes, "The recursive SQL query must pass start_node as bound parameters to execute()"
    assert re.search(r"[?:@$][A-Za-z_0-9]*", source), "No SQLite parameter placeholder was found"


def test_authorized_request_correct_traversal():
    url = f"{BASE_URL}/trace?start_node=NODE_77"
    try:
        response = requests.get(url, headers=AUTH_HEADER, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "infected_nodes" in data, "Response JSON missing 'infected_nodes' key"

    expected_nodes = {"NODE_77", "NODE_80", "NODE_81", "NODE_90", "NODE_95"}
    actual_nodes = set(data["infected_nodes"])

    assert actual_nodes == expected_nodes, f"Expected nodes {expected_nodes}, got {actual_nodes}"
    assert len(data["infected_nodes"]) == len(actual_nodes), "Response contains duplicated nodes, deduplication failed"
    assert set(data.keys()) == {"infected_nodes"}, f"Response must contain exactly the infected_nodes key, got {set(data.keys())}"


def test_unauthorized_request_no_header():
    url = f"{BASE_URL}/trace?start_node=NODE_77"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API: {e}")

    assert response.status_code == 401, f"Expected status code 401 for missing auth header, got {response.status_code}"


def test_unauthorized_request_wrong_token():
    url = f"{BASE_URL}/trace?start_node=NODE_77"
    headers = {"Authorization": "Bearer wrong-token"}
    try:
        response = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API: {e}")

    assert response.status_code == 401, f"Expected status code 401 for wrong token, got {response.status_code}"


def test_sql_injection_prevention():
    url = f"{BASE_URL}/trace?start_node=NODE_77' OR '1'='1"
    try:
        response = requests.get(url, headers=AUTH_HEADER, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API: {e}")

    assert response.status_code == 200, f"Expected status code 200 (graceful handling of special characters via parameterization), got {response.status_code}"

    data = response.json()
    actual_nodes = set(data.get("infected_nodes", []))
    assert "NODE_80" not in actual_nodes, "SQL injection vulnerability detected; query returned unrelated nodes."


def test_live_service_uses_database_for_randomized_traversals(randomized_graph):
    starts = [
        randomized_graph["root"],
        randomized_graph["left"],
        randomized_graph["shared"],
        "NODE_10",
        f"UNKNOWN_{uuid.uuid4().hex}",
    ]
    for start in starts:
        try:
            response = requests.get(
                f"{BASE_URL}/trace",
                params={"start_node": start},
                headers=AUTH_HEADER,
                timeout=5,
            )
        except requests.exceptions.RequestException as e:
            pytest.fail(f"Failed to connect to the API for start node {start!r}: {e}")

        assert response.status_code == 200, f"Expected 200 for {start!r}, got {response.status_code}: {response.text}"
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response is not valid JSON: {response.text}")
        assert_exact_payload(data, closure_from_database(start))


def test_submitted_api_artifact_directly(randomized_graph, submitted_app):
    client = submitted_app.test_client()
    for start in [randomized_graph["root"], randomized_graph["left"], "NODE_77"]:
        response = client.get(
            "/trace",
            query_string={"start_node": start},
            headers=AUTH_HEADER,
        )
        assert response.status_code == 200, f"Submitted app returned {response.status_code} for {start!r}"
        data = response.get_json()
        assert_exact_payload(data, closure_from_database(start))

    assert client.get("/trace", query_string={"start_node": randomized_graph["root"]}).status_code == 401
    assert client.get(
        "/trace",
        query_string={"start_node": randomized_graph["root"]},
        headers={"Authorization": "Bearer wrong-token"},
    ).status_code == 401
TEST_EOF

set +e
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
