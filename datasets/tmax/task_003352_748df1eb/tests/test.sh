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
import re
import signal
import socket
import sqlite3
import subprocess
import time
import uuid

import pytest
import requests

COMPUTE = "/home/user/compute_metrics.sh"
SERVE = "/home/user/serve.sh"
DB = "/home/user/graph.db"
OUTPUT = "/home/user/top_nodes.json"
URL = "http://127.0.0.1:8080/api/top_nodes"
ORIGINAL_EXPECTED = [
    {"node_id": "N1", "centrality": 4},
    {"node_id": "N2", "centrality": 2},
    {"node_id": "N3", "centrality": 0},
]


def load_output():
    assert os.path.exists(OUTPUT), f"File {OUTPUT} does not exist. Did you run the compute script and save the output?"
    with open(OUTPUT, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT} does not contain valid JSON.")


def check_response(expected, exact_body=None):
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API server at {URL}. Is the server running? Error: {e}")

    assert response.status_code == 200, f"Expected HTTP status 200, got {response.status_code}. Response: {response.text}"
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, f"Expected Content-Type to contain 'application/json', got '{content_type}'"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON. Response text: {response.text}")
    assert data == expected, f"API response JSON does not match expected output. Expected {expected}, got {data}"
    if exact_body is not None:
        assert response.content == exact_body, "API response body is not the exact contents of top_nodes.json"


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and int(fields[1].split(":")[1], 16) == port and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(name))
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def stop_port(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(0.3)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def run_script(path, timeout=10):
    try:
        result = subprocess.run([path], cwd="/home/user", text=True, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        pytest.fail(f"{path} did not return; it must launch its service in the background")
    assert result.returncode == 0, f"{path} failed with status {result.returncode}:\nstdout: {result.stdout}\nstderr: {result.stderr}"


def test_complete_solution():
    for path in (COMPUTE, SERVE):
        assert os.path.isfile(path), f"Required Bash script {path} is missing or is not a regular file"
        assert os.access(path, os.X_OK), f"Required script {path} is not executable"
        with open(path, "r", errors="replace") as f:
            text = f.read()
        assert text.startswith("#!") and "bash" in text.splitlines()[0], f"{path} must be a Bash script"
        assert not re.search(r"\b(python|python3|perl|ruby|php)\b", text, re.I), f"{path} uses a disallowed non-Bash implementation"

    with open(COMPUTE, "r", errors="replace") as f:
        compute_text = f.read().lower()
    assert "sqlite3" in compute_text, "compute_metrics.sh must query SQLite"
    assert "nodes" in compute_text and "edges" in compute_text, "compute_metrics.sh must query the graph tables"
    assert "group_id" in compute_text, "compute_metrics.sh does not include the required composite group key"

    # Preserve the original file assertion, then prove compute_metrics.sh creates it.
    data = load_output()
    assert data == ORIGINAL_EXPECTED, f"JSON content in {OUTPUT} does not match expected output. Expected {ORIGINAL_EXPECTED}, got {data}"
    run_script(COMPUTE)
    data = load_output()
    assert data == ORIGINAL_EXPECTED, f"JSON content in {OUTPUT} does not match expected output. Expected {ORIGINAL_EXPECTED}, got {data}"

    # Preserve the original HTTP assertions against the server the agent launched.
    check_response(ORIGINAL_EXPECTED)

    # Replace the database with an unpredictable graph to reject hardcoded output.
    token = uuid.uuid4().hex
    ids = [f"X{i}_{token}" for i in range(5)]
    groups = [f"GA_{token}", f"GB_{token}"]
    nodes = [
        (ids[0], groups[0]), (ids[0], groups[1]),
        (ids[1], groups[0]), (ids[2], groups[1]),
        (ids[3], groups[0]), (ids[4], groups[1]),
    ]
    edges = [
        (ids[0], ids[1], groups[0]),
        (ids[0], ids[2], groups[0]),
        (ids[0], ids[3], groups[1]),
        (ids[1], ids[0], groups[0]),
        (ids[1], ids[2], groups[0]),
        (ids[3], ids[0], groups[0]),
        (ids[3], ids[4], groups[0]),
    ]

    counts = {node_id: 0 for node_id, _ in nodes}
    node_keys = set(nodes)
    for src, dst, group_id in edges:
        if (src, group_id) in node_keys:
            counts[src] += 1
    expected = [
        {"node_id": node_id, "centrality": count}
        for node_id, count in sorted(counts.items(), key=lambda item: (-item[1], item[0]))[:3]
    ]

    os.unlink(DB)
    conn = sqlite3.connect(DB)
    try:
        conn.execute("CREATE TABLE nodes (id TEXT, group_id TEXT)")
        conn.execute("CREATE TABLE edges (src TEXT, dst TEXT, group_id TEXT)")
        conn.executemany("INSERT INTO nodes VALUES (?, ?)", nodes)
        conn.executemany("INSERT INTO edges VALUES (?, ?, ?)", edges)
        conn.commit()
    finally:
        conn.close()

    run_script(COMPUTE)
    dynamic_data = load_output()
    assert dynamic_data == expected, f"compute_metrics.sh produced {dynamic_data}; expected {expected} for the verification graph"

    # Stop any pre-existing listener and execute serve.sh itself.
    stop_port(8080)
    run_script(SERVE, timeout=5)

    deadline = time.time() + 5
    last_error = None
    while time.time() < deadline:
        try:
            with open(OUTPUT, "rb") as f:
                exact_body = f.read()
            check_response(expected, exact_body)
            break
        except (AssertionError, requests.exceptions.RequestException) as e:
            last_error = e
            time.sleep(0.2)
    else:
        pytest.fail(f"serve.sh did not provide the required API response: {last_error}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
