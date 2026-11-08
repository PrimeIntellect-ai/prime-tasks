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
import asyncio
import csv
import json
import os
import random
import subprocess
import sys
import time
import threading

import pytest
import requests

RAW_DIR = "/home/user/raw_data"
GRAPH_PATH = "/home/user/processed_graph.json"


def _candidate_processing_scripts():
    candidates = []
    for root in ("/home/user", "/app", "/tmp"):
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            if dirpath.startswith("/app/graph_transaction_lib"):
                continue
            for filename in filenames:
                if not filename.endswith(".py"):
                    continue
                path = os.path.join(dirpath, filename)
                if path == __file__:
                    continue
                try:
                    text = open(path, "r", encoding="utf-8").read()
                except (OSError, UnicodeDecodeError):
                    continue
                upper = text.upper()
                if ("SQLITE3" in upper and "PROCESSED_GRAPH.JSON" in upper
                        and "RAW_DATA" in upper and "OVER" in upper
                        and "PARTITION BY" in upper):
                    candidates.append(path)
    return candidates


def _dynamic_graph_is_correct(expected_nodes, expected_edges):
    try:
        with open(GRAPH_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return False

    if set(data) != {"nodes", "edges"}:
        return False
    if not isinstance(data["nodes"], list) or not isinstance(data["edges"], list):
        return False
    if any(set(node) != {"id", "name"} for node in data["nodes"]):
        return False
    if any(set(edge) != {"source", "target", "weight"} for edge in data["edges"]):
        return False

    actual_nodes = {(node["id"], node["name"]) for node in data["nodes"]}
    if actual_nodes != set(expected_nodes):
        return False

    actual_edges = {(edge["source"], edge["target"]): edge["weight"] for edge in data["edges"]}
    if set(actual_edges) != set(expected_edges):
        return False
    return all(abs(float(actual_edges[key]) - value) < 1e-8
               for key, value in expected_edges.items())


def test_processing_script_executes_on_unseen_input_using_window_query():
    candidates = _candidate_processing_scripts()
    assert candidates, "No Python data-processing script using sqlite3 and an OVER(PARTITION BY ...) query was found."

    paths = [os.path.join(RAW_DIR, "nodes.csv"), os.path.join(RAW_DIR, "edges.csv"), GRAPH_PATH]
    backups = {}
    for path in paths:
        backups[path] = open(path, "rb").read() if os.path.exists(path) else None

    rng = random.SystemRandom()
    base = rng.randrange(1000, 9000) * 10
    ids = [base + i for i in (1, 3, 7, 9)]
    names = [(ids[0], "Researcher_%d" % rng.randrange(100000, 999999)),
             (ids[1], "Researcher_%d" % rng.randrange(100000, 999999)),
             (ids[2], "Researcher_%d" % rng.randrange(100000, 999999)),
             (ids[3], "Researcher_%d" % rng.randrange(100000, 999999))]
    maximum = rng.randrange(17, 40)
    smaller = rng.randrange(2, maximum)
    second_maximum = rng.randrange(41, 70)
    second_smaller = rng.randrange(3, second_maximum)
    raw_edges = [(ids[0], ids[1], maximum), (ids[0], ids[2], smaller),
                 (ids[1], ids[3], second_maximum), (ids[1], ids[2], second_smaller),
                 (ids[2], ids[3], 13)]
    expected_edges = {
        (ids[0], ids[1]): 1.0,
        (ids[0], ids[2]): smaller / maximum,
        (ids[1], ids[3]): 1.0,
        (ids[1], ids[2]): second_smaller / second_maximum,
        (ids[2], ids[3]): 1.0,
    }

    processes = []
    try:
        os.makedirs(RAW_DIR, exist_ok=True)
        with open(paths[0], "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["node_id", "researcher_name"])
            writer.writerows(names)
        with open(paths[1], "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["source_id", "target_id", "raw_collaborations"])
            writer.writerows(raw_edges)
        if os.path.exists(GRAPH_PATH):
            os.unlink(GRAPH_PATH)

        succeeded = False
        errors = []
        for script in candidates:
            if os.path.exists(GRAPH_PATH):
                os.unlink(GRAPH_PATH)
            proc = subprocess.Popen(
                [sys.executable, script], cwd=os.path.dirname(script) or "/",
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                env=dict(os.environ, PYTHONUNBUFFERED="1"))
            processes.append(proc)
            deadline = time.time() + 8
            while time.time() < deadline:
                if _dynamic_graph_is_correct(names, expected_edges):
                    succeeded = True
                    break
                if proc.poll() is not None:
                    break
                time.sleep(0.1)
            if not succeeded and _dynamic_graph_is_correct(names, expected_edges):
                succeeded = True
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=2)
            if not succeeded:
                try:
                    out, err = proc.communicate(timeout=1)
                    errors.append(f"{script}: {(out + err).decode(errors='replace')[-500:]}")
                except Exception:
                    errors.append(f"{script}: did not produce the required graph")
            if succeeded:
                break

        assert succeeded, "No processing script generated the normalized graph for unseen CSV input. " + " | ".join(errors)
    finally:
        for proc in processes:
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=2)
        for path, content in backups.items():
            if content is None:
                if os.path.exists(path):
                    os.unlink(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)


def test_processed_graph_exists_and_correct():
    path = "/home/user/processed_graph.json"
    assert os.path.isfile(path), f"Processed graph file {path} does not exist."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not valid JSON.")

    assert "nodes" in data, "Processed graph missing 'nodes' key."
    assert "edges" in data, "Processed graph missing 'edges' key."

    node_ids = {n.get("id") for n in data["nodes"]}
    assert {1, 2, 3, 4}.issubset(node_ids), "Missing expected node IDs in processed graph."

    edges_map = {(e.get("source"), e.get("target")): e.get("weight") for e in data["edges"]}
    expected_edges = {
        (1, 2): 1.0,
        (1, 3): 0.5,
        (2, 4): 1.0,
        (3, 4): 1.0
    }

    for edge, expected_weight in expected_edges.items():
        assert edge in edges_map, f"Edge {edge} missing in processed graph."
        assert abs(edges_map[edge] - expected_weight) < 1e-6, f"Edge {edge} has incorrect weight. Expected {expected_weight}, got {edges_map[edge]}."


def test_vendored_graph_opposite_updates_do_not_deadlock_and_change_state():
    from graph_transaction_lib import ThreadSafeGraph

    async def exercise():
        graph = ThreadSafeGraph()
        rng = random.SystemRandom()
        a, b = rng.sample(range(10000, 20000), 2)
        w1 = rng.random() + 0.25
        w2 = rng.random() + 1.5
        await asyncio.wait_for(
            asyncio.gather(graph.update_edge(a, b, w1), graph.update_edge(b, a, w2)),
            timeout=2.0)
        assert graph.edges[(a, b)] == w1
        assert graph.edges[(b, a)] == w2

    asyncio.run(exercise())


def test_api_server_shortest_path():
    url = "http://127.0.0.1:8080/shortest_path?src=1&dst=4"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API server or request timed out: {e}")

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Response is not valid JSON: {response.text}")

    assert "path" in data, "Response missing 'path' key."
    assert "total_weight" in data, "Response missing 'total_weight' key."
    assert data["path"] == [1, 3, 4] or data["path"] == ["1", "3", "4"], f"Incorrect shortest path. Expected [1, 3, 4], got {data['path']}."
    assert abs(float(data["total_weight"]) - 1.5) < 1e-6, f"Incorrect total weight. Expected 1.5, got {data['total_weight']}."


def test_api_server_concurrent_updates_no_deadlock():
    url = "http://127.0.0.1:8080/update_edge"

    def update_edge(src, dst, weight, results, index):
        try:
            resp = requests.post(url, json={"source": src, "target": dst, "weight": weight}, timeout=5)
            results[index] = resp.status_code
        except Exception as e:
            results[index] = str(e)

    results = [None, None]
    t1 = threading.Thread(target=update_edge, args=(1, 2, 2.0, results, 0))
    t2 = threading.Thread(target=update_edge, args=(2, 1, 3.0, results, 1))

    start_time = time.time()
    t1.start()
    t2.start()
    t1.join(timeout=5)
    t2.join(timeout=5)
    duration = time.time() - start_time

    assert t1.is_alive() is False and t2.is_alive() is False, "Concurrent requests deadlocked or timed out."
    assert results[0] == 200, f"Request 1 failed: {results[0]}"
    assert results[1] == 200, f"Request 2 failed: {results[1]}"
    assert duration < 5, f"Concurrent requests took too long ({duration}s), indicating potential deadlock or timeout."


def _get_path(src, dst):
    response = requests.get(
        "http://127.0.0.1:8080/shortest_path",
        params={"src": src, "dst": dst}, timeout=5)
    assert response.status_code == 200, response.text
    data = response.json()
    assert set(data) >= {"path", "total_weight"}
    return [int(x) for x in data["path"]], float(data["total_weight"])


def _post_edge(src, dst, weight):
    response = requests.post(
        "http://127.0.0.1:8080/update_edge",
        json={"source": src, "target": dst, "weight": weight}, timeout=5)
    assert response.status_code == 200, response.text
    assert response.json() == {"status": "ok"}


def test_api_updates_change_shortest_path_state_with_unseen_weights():
    rng = random.SystemRandom()
    direct_weight = rng.uniform(0.02, 0.20)
    changed_weight = rng.uniform(0.21, 0.40)

    _post_edge(1, 4, direct_weight)
    path, total = _get_path(1, 4)
    assert path == [1, 4]
    assert abs(total - direct_weight) < 1e-6

    _post_edge(1, 4, 10.0 + rng.random())
    _post_edge(1, 3, changed_weight)
    path, total = _get_path(1, 4)
    assert path == [1, 3, 4]
    assert abs(total - (changed_weight + 1.0)) < 1e-6

    path, total = _get_path(1, 3)
    assert path == [1, 3]
    assert abs(total - changed_weight) < 1e-6
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
