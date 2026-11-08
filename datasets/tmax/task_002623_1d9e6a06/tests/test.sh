#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import stat
import subprocess
import tempfile
import time

import networkx as nx
import pytest
import requests

URL = "http://127.0.0.1:8080/metric"
SCRIPT = "/home/user/process.py"
DATASET = "/app/dataset.jsonl"


def test_metric_endpoint():
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {URL}. Is the server running? Error: {e}")

    assert response.status_code == 200, f"Expected HTTP status code 200, got {response.status_code}. Response body: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response body: {response.text}")

    expected_scores = {
        "A": 0.2644,
        "B": 0.1472,
        "C": 0.3797,
        "D": 0.2087
    }

    for node, expected_score in expected_scores.items():
        assert node in data, f"Missing node '{node}' in the JSON response."
        actual_score = data[node]
        assert isinstance(actual_score, (int, float)), f"Score for node '{node}' is not a number: {actual_score}"
        assert abs(actual_score - expected_score) <= 0.001, (
            f"Score for node '{node}' is incorrect. "
            f"Expected ~{expected_score}, got {actual_score}. "
            "Did you use the correct metric (pagerank) and parameter (alpha=0.85)?"
        )


def listener_pids(port=8080):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    found = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid in (1, os.getpid()):
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.add(pid)
                    break
        except OSError:
            pass
    return found


def stop_server():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
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
    assert not listener_pids(), "Could not stop the existing server on port 8080"


def expected_for(rows):
    graph = nx.DiGraph()
    for row in rows:
        graph.add_node(row["src"])
        for dst in row["dst"]:
            graph.add_edge(row["src"], dst)
    return {node: round(score, 4) for node, score in nx.pagerank(graph, alpha=0.85).items()}


def query_started_script(rows):
    with open(DATASET, "w") as f:
        for row in rows:
            f.write(json.dumps(row) + "\n")

    log = tempfile.TemporaryFile(mode="w+")
    proc = subprocess.Popen(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdout=log,
        stderr=subprocess.STDOUT,
        env={**os.environ, "PYTHONUNBUFFERED": "1"},
    )

    response = None
    last_error = None
    deadline = time.time() + 12
    while time.time() < deadline:
        try:
            response = requests.get(URL, timeout=1)
            break
        except requests.exceptions.RequestException as exc:
            last_error = exc
            if proc.poll() is not None and not listener_pids():
                break
            time.sleep(0.15)

    if response is None:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
        log.seek(0)
        output = log.read()
        log.close()
        pytest.fail(f"Executing {SCRIPT} did not start the required server: {last_error}\nOutput:\n{output}")

    try:
        assert response.status_code == 200, response.text
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response from executed process.py is not JSON: {response.text}")
        return data
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
        stop_server()
        log.close()


def make_random_dataset():
    token = secrets.token_hex(6)
    nodes = [f"verify_{token}_{i}" for i in range(7)]
    rows = []
    for i, src in enumerate(nodes):
        dst = [node for j, node in enumerate(nodes) if i != j and secrets.randbelow(100) < 35]
        if not dst:
            dst = [nodes[(i + 1) % len(nodes)]]
        rows.append({"src": src, "dst": dst})
    return rows


def assert_dynamic_result(rows, data):
    expected = expected_for(rows)
    assert isinstance(data, dict), f"Expected a JSON object, got {type(data).__name__}"
    assert set(data) == set(expected), f"Unexpected node set: expected {set(expected)}, got {set(data)}"
    for node, score in expected.items():
        actual = data[node]
        assert isinstance(actual, (int, float)) and not isinstance(actual, bool), f"Score for {node} is not numeric: {actual}"
        assert abs(actual - score) <= 0.000051, (
            f"Incorrect PageRank for {node} on an altered dataset: expected {score}, got {actual}"
        )


def test_process_script_on_altered_datasets():
    assert os.path.exists(SCRIPT), f"Missing required script: {SCRIPT}"
    assert stat.S_ISREG(os.lstat(SCRIPT).st_mode), f"{SCRIPT} must be a regular Python file"

    with open(DATASET, "rb") as f:
        original_dataset = f.read()

    stop_server()
    try:
        for _ in range(2):
            rows = make_random_dataset()
            data = query_started_script(rows)
            assert_dynamic_result(rows, data)
    finally:
        stop_server()
        with open(DATASET, "wb") as f:
            f.write(original_dataset)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
