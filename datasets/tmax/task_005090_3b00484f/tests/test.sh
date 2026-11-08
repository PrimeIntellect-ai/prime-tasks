#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import subprocess
import sys
import time
import uuid
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed

import pytest
import requests

BASE_URL = "http://localhost:8080"


def wait_for_server():
    max_retries = 10
    for _ in range(max_retries):
        try:
            requests.get(BASE_URL, timeout=1)
            return True
        except requests.exceptions.RequestException:
            time.sleep(0.5)
    return False


def post_edges_concurrently(edges, workers=10):
    def post_edge(edge):
        response = requests.post(f"{BASE_URL}/edge", json=edge, timeout=7)
        response.raise_for_status()
        assert response.status_code in (200, 201)
        return response.status_code

    successes = 0
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = [executor.submit(post_edge, edge) for edge in edges]
        for future in as_completed(futures):
            try:
                future.result()
                successes += 1
            except Exception as exc:
                pytest.fail(
                    f"Concurrent POST request failed or timed out: {exc}. "
                    "This likely indicates a deadlock in TinyDB."
                )
    assert successes == len(edges)


def get_aggregate():
    response = requests.get(f"{BASE_URL}/aggregate", timeout=7)
    response.raise_for_status()
    return response.json()


def test_fastapi_app_exists():
    assert os.path.isfile("/app/main.py"), "The FastAPI app file /app/main.py does not exist."


def test_server_is_running():
    assert wait_for_server(), "FastAPI server is not reachable on localhost:8080."


def test_vendored_tinydb_is_used_and_storage_no_longer_deadlocks():
    import tinydb

    module_path = os.path.realpath(tinydb.__file__)
    assert module_path.startswith("/app/tinydb/"), (
        f"tinydb must be installed from /app/tinydb, but imported from {module_path}"
    )

    with open("/app/main.py", "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read(), filename="/app/main.py")
    imports_tinydb = any(
        (isinstance(node, ast.Import) and any(alias.name == "tinydb" for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module == "tinydb")
        for node in ast.walk(tree)
    )
    assert imports_tinydb, "/app/main.py must import and use the vendored tinydb backend."

    # The shipped perturbation acquires JSONStorage's lock on every write but never
    # releases it. Two writes through one storage object therefore hang. Exercise
    # that exact path in an isolated process so a failure cannot hang the verifier.
    code = r'''
from tinydb.storages import JSONStorage
p = "/tmp/verifier_storage_%s.json"
s = JSONStorage(p)
s.write({"_default": {"1": {"value": 1}}})
s.write({"_default": {"1": {"value": 2}}})
s.close()
''' % uuid.uuid4().hex
    try:
        result = subprocess.run(
            [sys.executable, "-c", code], capture_output=True, text=True, timeout=5
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Vendored TinyDB JSONStorage still deadlocks on repeated writes.")
    assert result.returncode == 0, result.stderr


def test_concurrent_inserts_and_aggregation():
    # Preserve the original fixed workload and assertions.
    edges = []
    for i in range(10):
        edges.append({"src": "test_A", "dst": f"test_dst_{i}", "weight": 1})
        edges.append({"src": "test_B", "dst": f"test_dst_{i}", "weight": 2})
        edges.append({"src": "test_C", "dst": f"test_dst_{i}", "weight": 3})
        edges.append({"src": "test_D", "dst": f"test_dst_{i}", "weight": 4})
        edges.append({"src": "test_E", "dst": f"test_dst_{i}", "weight": 5})

    post_edges_concurrently(edges, workers=10)
    data = get_aggregate()
    assert isinstance(data, list), "Aggregate response must be a JSON list."

    test_nodes_data = [item for item in data if str(item.get("node", "")).startswith("test_")]
    expected_degrees = {
        "test_E": 50,
        "test_D": 40,
        "test_C": 30,
        "test_B": 20,
        "test_A": 10,
    }
    actual_degrees = {item["node"]: item["out_degree"] for item in test_nodes_data}
    for node, expected_weight in expected_degrees.items():
        assert actual_degrees.get(node) == expected_weight, (
            f"Expected out_degree for {node} to be {expected_weight}, "
            f"got {actual_degrees.get(node)}"
        )

    sorted_test_data = sorted(test_nodes_data, key=lambda item: (-item["out_degree"], item["node"]))
    returned_test_nodes = [item["node"] for item in test_nodes_data]
    expected_test_nodes = [item["node"] for item in sorted_test_data]
    assert returned_test_nodes == expected_test_nodes, (
        "The aggregate results are not sorted correctly (out_degree DESC, node ASC)."
    )


def test_unpredictable_stream_is_persisted_and_aggregated_exactly():
    # Values are generated only at verification time, preventing a service from
    # returning aggregates hardcoded for the original five nodes.
    token = uuid.uuid4().hex
    rng = random.SystemRandom()
    nodes = [f"verify_{token}_{i:02d}" for i in range(12)]
    dynamic_edges = []
    expected = {node: 0 for node in nodes}

    for node_index, node in enumerate(nodes):
        for edge_index in range(8):
            weight = rng.randint(1, 50)
            edge = {
                "src": node,
                "dst": f"dst_{token}_{node_index}_{edge_index}_{uuid.uuid4().hex}",
                "weight": weight,
            }
            dynamic_edges.append(edge)
            expected[node] += weight

    rng.shuffle(dynamic_edges)
    post_edges_concurrently(dynamic_edges, workers=20)

    data = get_aggregate()
    assert isinstance(data, list), "Aggregate response must be a JSON list."

    # Strictly validate the complete response schema and global ordering.
    for item in data:
        assert isinstance(item, dict), "Every aggregate entry must be a JSON object."
        assert set(item.keys()) == {"node", "out_degree"}, (
            "Every aggregate entry must contain exactly node and out_degree."
        )
        assert isinstance(item["node"], str), "Aggregate node values must be strings."
        assert isinstance(item["out_degree"], int) and not isinstance(item["out_degree"], bool), (
            "Aggregate out_degree values must be integers."
        )
    assert len({item["node"] for item in data}) == len(data), (
        "Aggregate must contain exactly one object per source node."
    )
    assert data == sorted(data, key=lambda item: (-item["out_degree"], item["node"])), (
        "The complete aggregate list is not sorted by out_degree DESC, node ASC."
    )

    actual = {item["node"]: item["out_degree"] for item in data if item["node"] in expected}
    assert actual == expected, f"Dynamic aggregate mismatch: expected {expected}, got {actual}"

    assert os.path.isfile("/app/graph.json"), "Edges were not persisted to /app/graph.json."
    assert os.path.getsize("/app/graph.json") > 0, "/app/graph.json is empty."

    # Read the required backing file through the installed TinyDB implementation and
    # ensure every unpredictable POST is represented by a stored edge document.
    from tinydb import TinyDB

    db = TinyDB("/app/graph.json")
    try:
        documents = db.all()
    finally:
        db.close()

    stored = Counter(
        (doc.get("src"), doc.get("dst"), doc.get("weight"))
        for doc in documents
        if isinstance(doc, dict) and doc.get("src") in expected
    )
    submitted = Counter((edge["src"], edge["dst"], edge["weight"]) for edge in dynamic_edges)
    for edge_key, count in submitted.items():
        assert stored[edge_key] >= count, f"Posted edge was not persisted in TinyDB: {edge_key}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
