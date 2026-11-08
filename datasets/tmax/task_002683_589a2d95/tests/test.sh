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
import os
import random
import signal
import subprocess
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"
NODES_CSV = "/home/user/data/nodes.csv"
EDGES_CSV = "/home/user/data/edges.csv"
BINARY = "/home/user/graph_server"
LOG_PATH = "/home/user/server.log"
ORACLE = "/app/kg_oracle"
HIDDEN_ORACLE = "/app/kg_oracle.verifier_hidden"


def get_nodes():
    nodes = {}
    with open(NODES_CSV, newline="") as f:
        for row in csv.DictReader(f):
            nodes[row["node_id"]] = row["node_type"]
    return nodes


def get_edges():
    edges = []
    with open(EDGES_CSV, newline="") as f:
        for row in csv.DictReader(f):
            edges.append({"src": row["src_id"], "dst": row["dst_id"], "rel": row["relation_type"]})
    return edges


def listener_pids(port=9090):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        if int(fields[1].rsplit(":", 1)[1], 16) == port:
                            inodes.add(fields[9])
        except OSError:
            pass

    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except OSError:
            pass
    return pids


def stop_port():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids():
        time.sleep(0.05)
    assert not listener_pids(), "Could not stop the existing server on port 9090"


def assert_json_content_type(response):
    assert response.headers.get("Content-Type", "").lower().split(";", 1)[0].strip() == "application/json"


def test_server_binary_exists():
    assert os.path.isfile(BINARY), "/home/user/graph_server binary does not exist."
    assert os.access(BINARY, os.X_OK), "/home/user/graph_server is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/graph_server must be a compiled native executable."


def test_server_log_exists():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."
    with open(LOG_PATH) as f:
        content = f.read()
    assert "SERVER READY" in content, f"'SERVER READY' not found in {LOG_PATH}."


def test_pattern_endpoint():
    nodes = get_nodes()
    edges = get_edges()
    expected_matches = []
    for e in edges:
        if e["rel"] == "WorksFor":
            if nodes.get(e["src"]) == "Person" and nodes.get(e["dst"]) == "Company":
                expected_matches.append([e["src"], e["dst"]])
    expected_matches.sort()

    try:
        response = requests.get(
            f"{BASE_URL}/pattern?src_type=Person&dst_type=Company&rel=WorksFor", timeout=5
        )
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to pattern endpoint: {e}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    assert_json_content_type(response)
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")
    assert isinstance(data, list), "Response should be a JSON array"
    actual_matches = sorted([list(match) for match in data])
    assert actual_matches == expected_matches, f"Pattern matches do not match expected. Expected {len(expected_matches)} matches."


def test_influence_endpoint():
    edges = get_edges()
    test_node = "105"
    in_degree = sum(1 for e in edges if e["dst"] == test_node)
    out_degree = sum(1 for e in edges if e["src"] == test_node)
    expected_score = (in_degree * 3) + (out_degree * 2)

    try:
        response = requests.get(f"{BASE_URL}/influence?node={test_node}", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to influence endpoint: {e}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    assert_json_content_type(response)
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")
    assert isinstance(data, dict), "Response should be a JSON object"
    assert "node" in data, "Response missing 'node' key"
    assert "score" in data, "Response missing 'score' key"
    assert str(data["node"]) == test_node, f"Expected node {test_node}, got {data['node']}"
    assert data["score"] == expected_score, f"Expected score {expected_score}, got {data['score']}"


def test_relaunched_binary_on_unseen_dataset_without_oracle():
    original_nodes = open(NODES_CSV, "rb").read()
    original_edges = open(EDGES_CSV, "rb").read()
    oracle_hidden = False
    proc = None

    try:
        stop_port()
        assert os.path.exists(ORACLE), "Expected oracle is missing before isolation test"
        if os.path.exists(HIDDEN_ORACLE):
            os.unlink(HIDDEN_ORACLE)
        os.replace(ORACLE, HIDDEN_ORACLE)
        oracle_hidden = True

        rng = random.Random(int.from_bytes(os.urandom(16), "big"))
        types = ["Person", "Company", "Project"]
        relations = ["WorksFor", "Owns", "ContributesTo"]
        generated_nodes = {str(i): rng.choice(types) for i in range(1, 201)}
        generated_edges = [
            {
                "src": str(rng.randint(1, 200)),
                "dst": str(rng.randint(1, 200)),
                "rel": rng.choice(relations),
            }
            for _ in range(500)
        ]

        with open(NODES_CSV, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["node_id", "node_type"])
            for node_id, node_type in generated_nodes.items():
                writer.writerow([node_id, node_type])
        with open(EDGES_CSV, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["src_id", "dst_id", "relation_type"])
            for edge in generated_edges:
                writer.writerow([edge["src"], edge["dst"], edge["rel"]])

        with open(LOG_PATH, "w") as log:
            proc = subprocess.Popen([BINARY], cwd="/home/user", stdout=log, stderr=subprocess.STDOUT)

        deadline = time.time() + 10
        last_error = None
        while time.time() < deadline:
            try:
                response = requests.get(f"{BASE_URL}/influence", params={"node": "1"}, timeout=0.5)
                if response.status_code == 200 and listener_pids():
                    with open(LOG_PATH) as f:
                        if "SERVER READY" in f.read():
                            break
            except (requests.RequestException, OSError) as e:
                last_error = e
            time.sleep(0.1)
        else:
            pytest.fail(f"Relaunched graph_server did not become ready: {last_error}")

        owners = listener_pids()
        assert owners, "No process owns the listening socket"
        native_owner = False
        for pid in owners:
            try:
                if os.path.samefile(f"/proc/{pid}/exe", BINARY):
                    native_owner = True
                    break
            except OSError:
                pass
        assert native_owner, "Port 9090 is not being served by the submitted native executable"

        for src_type in types:
            for dst_type in types:
                for relation in relations:
                    expected = sorted([
                        [e["src"], e["dst"]]
                        for e in generated_edges
                        if e["rel"] == relation
                        and generated_nodes[e["src"]] == src_type
                        and generated_nodes[e["dst"]] == dst_type
                    ])
                    response = requests.get(
                        f"{BASE_URL}/pattern",
                        params={"src_type": src_type, "dst_type": dst_type, "rel": relation},
                        timeout=5,
                    )
                    assert response.status_code == 200
                    assert_json_content_type(response)
                    data = response.json()
                    assert isinstance(data, list)
                    assert all(
                        isinstance(pair, list)
                        and len(pair) == 2
                        and all(isinstance(value, str) for value in pair)
                        for pair in data
                    )
                    assert sorted(data) == expected

        in_degree = {str(i): 0 for i in range(1, 201)}
        out_degree = {str(i): 0 for i in range(1, 201)}
        for edge in generated_edges:
            out_degree[edge["src"]] += 1
            in_degree[edge["dst"]] += 1

        for node_id in generated_nodes:
            expected_score = in_degree[node_id] * 3 + out_degree[node_id] * 2
            response = requests.get(f"{BASE_URL}/influence", params={"node": node_id}, timeout=5)
            assert response.status_code == 200
            assert_json_content_type(response)
            data = response.json()
            assert isinstance(data, dict)
            assert str(data.get("node")) == node_id
            assert isinstance(data.get("score"), int) and not isinstance(data.get("score"), bool)
            assert data["score"] == expected_score
    finally:
        try:
            stop_port()
        except Exception:
            pass
        with open(NODES_CSV, "wb") as f:
            f.write(original_nodes)
        with open(EDGES_CSV, "wb") as f:
            f.write(original_edges)
        if oracle_hidden and os.path.exists(HIDDEN_ORACLE):
            os.replace(HIDDEN_ORACLE, ORACLE)
        if proc is not None and proc.poll() is None:
            proc.kill()
            proc.wait(timeout=2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
