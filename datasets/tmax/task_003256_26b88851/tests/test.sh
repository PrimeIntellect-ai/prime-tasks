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
import concurrent.futures
import json
import os
import re
import secrets
import socket
import sqlite3
import time

import pytest
import requests

DB_PATH = "/app/knowledge.db"
BASE_URL = "http://127.0.0.1:8080"


def wait_for_server(url, timeout=8):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get(url, timeout=1)
            return True
        except requests.exceptions.RequestException:
            time.sleep(0.25)
    return False


@pytest.fixture(scope="session", autouse=True)
def server_is_running():
    url = f"{BASE_URL}/api/traverse?start_node=N1&edge_label=KNOWS&max_depth=1"
    assert wait_for_server(url), "HTTP server is not reachable on 127.0.0.1:8080"


def request_traversal(start_node, edge_label, max_depth, timeout=5):
    response = requests.get(
        f"{BASE_URL}/api/traverse",
        params={
            "start_node": start_node,
            "edge_label": edge_label,
            "max_depth": max_depth,
        },
        timeout=timeout,
    )
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}: {response.text}"
    )
    data = response.json()
    assert "reachable_nodes" in data, "Response JSON missing 'reachable_nodes' key"
    assert "count" in data, "Response JSON missing 'count' key"
    assert isinstance(data["reachable_nodes"], list)
    assert data["reachable_nodes"] == sorted(data["reachable_nodes"]), (
        "reachable_nodes must be sorted alphabetically"
    )
    assert data["count"] == len(data["reachable_nodes"])
    return data


def test_index_created():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_edge_opt'"
        )
        index = cursor.fetchone()
        assert index is not None, "Index 'idx_edge_opt' was not created in the database."

        cursor.execute("PRAGMA index_info(idx_edge_opt)")
        columns = [row[2] for row in cursor.fetchall()]
        assert "source_node" in columns and "edge_label" in columns, (
            "Index 'idx_edge_opt' does not cover the required columns "
            "(source_node, edge_label)."
        )
        assert columns[:2] == ["source_node", "edge_label"], (
            "idx_edge_opt must begin with source_node, edge_label as specified by the hint"
        )

        cursor.execute(
            """
            EXPLAIN QUERY PLAN
            WITH RECURSIVE traversal(node, depth) AS (
                SELECT target_node, 1
                FROM edges
                WHERE source_node = ? AND edge_label = ? AND is_deleted = 0
                UNION ALL
                SELECT e.target_node, traversal.depth + 1
                FROM edges AS e
                JOIN traversal ON e.source_node = traversal.node
                WHERE e.edge_label = ? AND e.is_deleted = 0
                  AND traversal.depth < ?
            )
            SELECT DISTINCT node FROM traversal
            """,
            ("N1", "KNOWS", "KNOWS", 3),
        )
        plan = "\n".join(str(row[3]) for row in cursor.fetchall())
        assert "idx_edge_opt" in plan, (
            f"SQLite does not use idx_edge_opt for the required traversal lookup. Plan:\n{plan}"
        )
    finally:
        conn.close()


def test_running_python_server_contains_recursive_cte():
    listener_inodes = set()
    for tcp_path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(tcp_path) as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    local_address = fields[1]
                    state = fields[3]
                    if int(local_address.rsplit(":", 1)[1], 16) == 8080 and state == "0A":
                        listener_inodes.add(fields[9])
        except OSError:
            pass
    assert listener_inodes, "No process is listening on TCP port 8080"

    listener_pids = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if any(target == f"socket:[{inode}]" for inode in listener_inodes):
                    listener_pids.append(int(entry))
                    break
        except OSError:
            continue

    assert listener_pids, "Could not identify the process listening on port 8080"
    source_material = []
    python_listener = False
    search_roots = {"/app", "/home/user"}

    for pid in listener_pids:
        try:
            raw_cmdline = open(f"/proc/{pid}/cmdline", "rb").read()
            args = [part.decode(errors="replace") for part in raw_cmdline.split(b"\0") if part]
            cmdline = " ".join(args)
            source_material.append(cmdline)
            exe = os.path.basename(os.readlink(f"/proc/{pid}/exe")).lower()
            python_listener = python_listener or "python" in exe or "python" in cmdline.lower()
            cwd = os.readlink(f"/proc/{pid}/cwd")
            search_roots.add(cwd)
            for arg in args:
                candidate = arg if os.path.isabs(arg) else os.path.join(cwd, arg)
                if os.path.isfile(candidate) and candidate.endswith(".py"):
                    with open(candidate, errors="replace") as handle:
                        source_material.append(handle.read())
        except OSError:
            continue

    assert python_listener, "The process listening on port 8080 is not a Python server"

    # Include Python modules stored in the normal task work areas, allowing a small
    # launcher script to import its traversal implementation from another module.
    for root in search_roots:
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in {".git", "__pycache__", "site-packages"}]
            for filename in filenames:
                if not filename.endswith(".py"):
                    continue
                path = os.path.join(dirpath, filename)
                try:
                    if os.path.getsize(path) <= 1024 * 1024:
                        with open(path, errors="replace") as handle:
                            source_material.append(handle.read())
                except OSError:
                    pass

    combined_source = "\n".join(source_material)
    assert re.search(r"\bWITH\s+RECURSIVE\b", combined_source, re.IGNORECASE), (
        "The running Python server implementation does not contain a Recursive CTE"
    )


def test_api_traverse_knows_depth_2():
    data = request_traversal("N1", "KNOWS", 2)
    expected_nodes = ["N2", "N3"]
    assert data["reachable_nodes"] == expected_nodes, (
        f"Expected reachable_nodes {expected_nodes}, got {data['reachable_nodes']}"
    )
    assert data["count"] == len(expected_nodes)


def test_api_traverse_likes_depth_1():
    data = request_traversal("N1", "LIKES", 1)
    expected_nodes = ["N7"]
    assert data["reachable_nodes"] == expected_nodes, (
        f"Expected reachable_nodes {expected_nodes}, got {data['reachable_nodes']}"
    )
    assert data["count"] == len(expected_nodes)


def test_api_traverse_filters_deleted():
    data = request_traversal("N1", "KNOWS", 3)
    expected_nodes = ["N2", "N3", "N4"]
    assert data["reachable_nodes"] == expected_nodes, (
        f"Expected reachable_nodes {expected_nodes}, got {data['reachable_nodes']} "
        "(Make sure deleted edges are filtered out)"
    )
    assert data["count"] == len(expected_nodes)


def expected_from_rows(rows, start_node, edge_label, max_depth):
    adjacency = {}
    for source, target, label, is_deleted in rows:
        if label == edge_label and is_deleted == 0:
            adjacency.setdefault(source, []).append(target)

    frontier = {start_node}
    reachable = set()
    for _ in range(max_depth):
        next_frontier = set()
        for node in frontier:
            next_frontier.update(adjacency.get(node, ()))
        reachable.update(next_frontier)
        frontier = next_frontier
    return sorted(reachable)


def test_api_queries_arbitrary_live_database_graph():
    token = secrets.token_hex(8)
    label = f"AUDIT_LABEL_{token}"
    other_label = f"AUDIT_OTHER_{token}"
    nodes = {name: f"AUDIT_{token}_{name}" for name in "SABCDEFGXYZQ"}
    rows = [
        (nodes["S"], nodes["A"], label, 0),
        (nodes["S"], nodes["B"], label, 0),
        (nodes["S"], nodes["X"], label, 1),
        (nodes["A"], nodes["C"], label, 0),
        (nodes["B"], nodes["C"], label, 0),
        (nodes["B"], nodes["E"], other_label, 0),
        (nodes["C"], nodes["D"], label, 0),
        (nodes["D"], nodes["A"], label, 0),
        (nodes["X"], nodes["Z"], label, 0),
        (nodes["Q"], nodes["G"], label, 0),
    ]

    conn = sqlite3.connect(DB_PATH, timeout=10)
    try:
        conn.executemany(
            "INSERT INTO edges(source_node,target_node,edge_label,is_deleted) VALUES(?,?,?,?)",
            rows,
        )
        conn.commit()

        # Expectations are computed from the freshly generated graph rather than
        # being constants known to the submitted server.
        for depth in (1, 2, 4):
            expected = expected_from_rows(rows, nodes["S"], label, depth)
            data = request_traversal(nodes["S"], label, depth)
            assert data["reachable_nodes"] == expected, (
                f"At depth {depth}, expected {expected}, got {data['reachable_nodes']}"
            )
            assert data["count"] == len(expected)

        empty = request_traversal(f"AUDIT_MISSING_{token}", label, 4)
        assert empty == {"reachable_nodes": [], "count": 0}
    finally:
        conn.execute(
            "DELETE FROM edges WHERE edge_label IN (?, ?)", (label, other_label)
        )
        conn.commit()
        conn.close()


def test_server_handles_requests_concurrently():
    # Hold one accepted HTTP connection open with an incomplete request. A
    # single-threaded HTTP server blocks waiting for its terminator, whereas a
    # concurrent server can still service the normal request below.
    slow = socket.create_connection(("127.0.0.1", 8080), timeout=2)
    try:
        slow.sendall(
            b"GET /api/traverse?start_node=N1&edge_label=KNOWS&max_depth=1 HTTP/1.1\r\n"
            b"Host: 127.0.0.1\r\n"
        )
        time.sleep(0.35)
        data = request_traversal("N1", "LIKES", 1, timeout=2)
        assert data["reachable_nodes"] == ["N7"]
    finally:
        slow.close()

    cases = [
        ("N1", "KNOWS", 1, ["N2"]),
        ("N1", "KNOWS", 2, ["N2", "N3"]),
        ("N1", "KNOWS", 3, ["N2", "N3", "N4"]),
        ("N1", "LIKES", 1, ["N7"]),
    ] * 4
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        futures = [pool.submit(request_traversal, a, b, c) for a, b, c, _ in cases]
        for future, case in zip(futures, cases):
            assert future.result()["reachable_nodes"] == case[3]
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
