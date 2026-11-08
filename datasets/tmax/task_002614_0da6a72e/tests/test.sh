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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import signal
import sqlite3
import subprocess
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8000"


def wait_for_server(url=BASE_URL, timeout=8):
    start = time.time()
    while time.time() - start < timeout:
        try:
            response = requests.get(url, timeout=0.5)
            if response.status_code in (200, 400, 404):
                return True
        except requests.RequestException:
            pass
        time.sleep(0.2)
    return False


def get_centrality(node_id):
    url = f"{BASE_URL}/api/centrality?node={node_id}"
    try:
        response = requests.get(url, timeout=2)
    except requests.RequestException as exc:
        pytest.fail(f"Request to {url} failed: {exc}")

    assert response.status_code == 200, (
        f"Expected HTTP 200 for node {node_id}, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response from {url} is not valid JSON: {response.text}")

    assert "node" in data, f"Key 'node' missing for node {node_id}: {data}"
    assert "centrality" in data, f"Key 'centrality' missing for node {node_id}: {data}"
    assert int(data["node"]) == node_id, f"Expected node {node_id}, got {data['node']}"
    return float(data["centrality"])


def listener_pid(port=8000):
    wanted = f"{port:04X}"
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as fh:
                next(fh)
                for line in fh:
                    fields = line.split()
                    if fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(entry)
        except OSError:
            continue
    raise AssertionError("Could not identify the process listening on port 8000")


def capture_process(pid):
    with open(f"/proc/{pid}/cmdline", "rb") as fh:
        argv = [part.decode("utf-8", "surrogateescape") for part in fh.read().split(b"\0") if part]
    assert argv, "The listening process has no restartable command line"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = os.environ.copy()
    try:
        with open(f"/proc/{pid}/environ", "rb") as fh:
            for item in fh.read().split(b"\0"):
                if b"=" in item:
                    key, value = item.split(b"=", 1)
                    env[key.decode("utf-8", "surrogateescape")] = value.decode("utf-8", "surrogateescape")
    except OSError:
        pass
    return argv, cwd, env


def stop_server(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 4
    while time.time() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            break
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    time.sleep(0.5)


def pagerank(nodes, edges, damping=0.85):
    nodes = list(nodes)
    n = len(nodes)
    rank = {node: 1.0 / n for node in nodes}
    outgoing = {node: [] for node in nodes}
    for source, target in edges:
        outgoing[source].append(target)

    for _ in range(1000):
        dangling = sum(rank[node] for node in nodes if not outgoing[node])
        updated = {node: (1.0 - damping) / n + damping * dangling / n for node in nodes}
        for source in nodes:
            if outgoing[source]:
                share = damping * rank[source] / len(outgoing[source])
                for target in outgoing[source]:
                    updated[target] += share
        if max(abs(updated[node] - rank[node]) for node in nodes) < 1e-12:
            return updated
        rank = updated
    return rank


def test_original_server_contract_and_results():
    assert wait_for_server(), f"Server is not reachable at {BASE_URL}"
    for node_id in (101, 103, 104):
        centrality = get_centrality(node_id)
        expected = 1.0 / 3.0
        assert abs(centrality - expected) < 0.02, (
            f"Expected centrality for node {node_id} near {expected}, got {centrality}"
        )


def test_pipeline_is_not_a_fixed_response_server():
    pid = listener_pid()
    argv, cwd, env = capture_process(pid)
    stop_server(pid)

    # Add an unpredictable active employee and reporting edges. Then replace
    # idx_status with a physically incomplete index whose schema claims it is
    # complete. A normal indexed status lookup misses active rows, while a
    # forced table scan still returns the true records described by the task.
    new_id = random.SystemRandom().randrange(200000, 900000)
    conn = sqlite3.connect("/app/company.db")
    conn.execute("INSERT INTO employees(emp_id, name, status) VALUES (?, ?, 'active')", (new_id, "Verifier Employee"))
    conn.execute("INSERT INTO employee_edges(source_id, target_id) VALUES (?, ?)", (104, new_id))
    conn.execute("INSERT INTO employee_edges(source_id, target_id) VALUES (?, ?)", (new_id, 101))
    conn.execute("DROP INDEX IF EXISTS idx_status")
    conn.execute("CREATE INDEX idx_status ON employees(status) WHERE status = 'inactive'")
    conn.commit()
    schema_version = conn.execute("PRAGMA schema_version").fetchone()[0]
    conn.execute("PRAGMA writable_schema=ON")
    conn.execute("UPDATE sqlite_schema SET sql='CREATE INDEX idx_status ON employees(status)' WHERE type='index' AND name='idx_status'")
    conn.execute(f"PRAGMA schema_version={schema_version + 1}")
    conn.commit()
    conn.close()

    subprocess.Popen(argv, cwd=cwd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    assert wait_for_server(timeout=10), "Server artifact did not restart after the input database changed"

    conn = sqlite3.connect("/app/company.db")
    active = {row[0] for row in conn.execute("SELECT emp_id FROM employees NOT INDEXED WHERE status='active'")}
    db_edges = {
        (source, target)
        for source, target in conn.execute("SELECT source_id, target_id FROM employee_edges")
        if source in active and target in active
    }
    conn.close()

    # The supplied voicemail contributes 104 -> 101.
    edges = db_edges | {(104, 101)}
    expected = pagerank(active, edges)
    for node_id in sorted(active):
        actual = get_centrality(node_id)
        assert abs(actual - expected[node_id]) < 1e-4, (
            f"Incorrect PageRank for node {node_id}: expected {expected[node_id]}, got {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
