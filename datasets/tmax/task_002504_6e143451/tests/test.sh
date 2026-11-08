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
import csv
import heapq
import io
import os
import secrets
import signal
import sqlite3
import subprocess
import time
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:8000"
TOKEN = "EchoTango77"
HEADERS = {"Authorization": f"Bearer {TOKEN}"}
DB = "/app/infrastructure.db"
DYNAMIC = {}
SERVER = None


def request(path, **kwargs):
    try:
        return requests.get(BASE_URL + path, timeout=5, **kwargs)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the API: {exc}")


def listener_pids(port=8000):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == "0A":
                try:
                    local_port = int(fields[1].rsplit(":", 1)[1], 16)
                except ValueError:
                    continue
                if local_port == port:
                    inodes.add(fields[9])

    pids = set()
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(proc.name))
                    break
        except OSError:
            continue
    return pids


def process_description(pid):
    proc = Path(f"/proc/{pid}")
    raw_argv = (proc / "cmdline").read_bytes().split(b"\0")
    argv = [x.decode(errors="surrogateescape") for x in raw_argv if x]
    assert argv, "Could not determine the API server command"
    cwd = os.readlink(proc / "cwd")
    executable = os.readlink(proc / "exe")
    env = {}
    for item in (proc / "environ").read_bytes().split(b"\0"):
        if b"=" in item:
            key, value = item.split(b"=", 1)
            env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    return argv, cwd, executable, env


def restart_server():
    global SERVER
    pids = listener_pids()
    assert pids, "No process is listening on port 8000"
    description = process_description(next(iter(pids)))

    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while listener_pids() and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    argv, cwd, executable, env = description
    SERVER = subprocess.Popen(
        argv,
        executable=executable,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    deadline = time.time() + 15
    last_error = None
    while time.time() < deadline:
        try:
            requests.get(BASE_URL + "/export", timeout=0.5)
            return
        except requests.exceptions.RequestException as exc:
            last_error = exc
            time.sleep(0.1)
    pytest.fail(f"API did not restart using its original command: {last_error}")


def test_01_unauthorized_access():
    response = request("/export")
    assert response.status_code in (401, 403), (
        f"Expected 401 or 403 for unauthorized access, got {response.status_code}"
    )


def test_02_shortest_path():
    response = request("/path?source=Gateway&target=DB_Main", headers=HEADERS)
    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "path" in data, "Response JSON missing 'path' key"
    assert "total_latency" in data, "Response JSON missing 'total_latency' key"
    assert data["path"] == ["Gateway", "AuthService", "Cache", "DB_Main"], (
        f"Incorrect path: {data['path']}"
    )
    assert data["total_latency"] == 35, f"Incorrect total_latency: {data['total_latency']}"


def test_03_csv_export():
    response = request("/export", headers=HEADERS)
    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )
    content_type = response.headers.get("Content-Type", "")
    assert "csv" in content_type.lower() or "text" in content_type.lower(), (
        f"Expected CSV content type, got {content_type}"
    )
    rows = list(csv.reader(io.StringIO(response.text.strip())))
    assert len(rows) >= 5, f"Expected at least 5 rows (header + 4 data rows), got {len(rows)}"
    assert rows[0] == ["node_name", "total_outgoing_latency"], (
        f"Incorrect CSV header: {rows[0]}"
    )
    expected_data = [
        ["Gateway", "110"],
        ["AuthService", "55"],
        ["Cache", "20"],
        ["DB_Main", "0"],
    ]
    for i, expected_row in enumerate(expected_data):
        assert rows[i + 1] == expected_row, (
            f"Row {i + 1} mismatch: expected {expected_row}, got {rows[i + 1]}"
        )


def test_04_add_unpredictable_fixture_and_restart():
    suffix = secrets.token_hex(8)
    names = [
        f"Source_{suffix}",
        f"Relay_{suffix}",
        f"Branch_{suffix}",
        f"Target_{suffix}",
        f"Quoted_{suffix}' OR 1=1 --",
    ]
    with sqlite3.connect(DB) as conn:
        first_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM nodes").fetchone()[0]
        ids = list(range(first_id, first_id + len(names)))
        conn.executemany("INSERT INTO nodes(id, name) VALUES (?, ?)", zip(ids, names))
        conn.executemany(
            "INSERT INTO edges(source_id, target_id, latency) VALUES (?, ?, ?)",
            [
                (ids[0], ids[1], 12),
                (ids[1], ids[2], 17),
                (ids[2], ids[3], 41),
                (ids[0], ids[2], 80),
                (ids[0], ids[3], 100),
                (ids[4], ids[3], 7),
            ],
        )
    DYNAMIC["names"] = names
    restart_server()


def expected_shortest_path(source, target):
    with sqlite3.connect(DB) as conn:
        node_rows = conn.execute("SELECT id, name FROM nodes").fetchall()
        edge_rows = conn.execute("SELECT source_id, target_id, latency FROM edges").fetchall()
    names = {node_id: name for node_id, name in node_rows}
    ids = {name: node_id for node_id, name in node_rows}
    graph = {node_id: [] for node_id in names}
    for source_id, target_id, latency in edge_rows:
        graph[source_id].append((target_id, latency))

    start, goal = ids[source], ids[target]
    queue = [(0, start, [start])]
    best = {}
    while queue:
        distance, node, path = heapq.heappop(queue)
        if node in best and best[node] <= distance:
            continue
        best[node] = distance
        if node == goal:
            return [names[x] for x in path], distance
        for neighbor, weight in graph.get(node, []):
            heapq.heappush(queue, (distance + weight, neighbor, path + [neighbor]))
    pytest.fail("Verifier fixture unexpectedly has no path")


def assert_path(source, target):
    expected_path, expected_latency = expected_shortest_path(source, target)
    response = request(
        "/path",
        headers=HEADERS,
        params={"source": source, "target": target},
    )
    assert response.status_code == 200, response.text
    data = response.json()
    assert data.get("path") == expected_path
    assert data.get("total_latency") == expected_latency


def test_05_dynamic_paths_and_parameter_safety():
    source, _, _, target, quoted = DYNAMIC["names"]
    assert_path(source, target)
    # A real node containing SQL metacharacters must be treated as data, not SQL.
    assert_path(quoted, target)


def test_06_exact_bearer_authentication():
    bad_headers = [
        {"Authorization": "Bearer definitely-wrong"},
        {"Authorization": f"Basic {TOKEN}"},
        {"Authorization": f"Bearer {TOKEN}extra"},
    ]
    for endpoint in ("/export", "/path?source=Gateway&target=DB_Main"):
        for headers in bad_headers:
            response = request(endpoint, headers=headers)
            assert response.status_code in (401, 403), (
                f"{endpoint} accepted incorrect authorization {headers!r}"
            )


def test_07_dynamic_csv_export():
    response = request("/export", headers=HEADERS)
    assert response.status_code == 200, response.text
    content_type = response.headers.get("Content-Type", "").split(";", 1)[0].strip().lower()
    assert content_type == "text/csv", f"Expected text/csv, got {response.headers.get('Content-Type')}"
    rows = list(csv.reader(io.StringIO(response.text)))
    assert rows and rows[0] == ["node_name", "total_outgoing_latency"]

    with sqlite3.connect(DB) as conn:
        expected = conn.execute(
            """
            SELECT n.name, COALESCE(SUM(e.latency), 0)
            FROM nodes AS n
            LEFT JOIN edges AS e ON e.source_id = n.id
            GROUP BY n.id, n.name
            """
        ).fetchall()
    actual = [(row[0], int(row[1])) for row in rows[1:]]
    assert len(actual) == len(expected), "CSV must contain exactly one row for every node"
    assert sorted(actual) == sorted(expected), "CSV aggregation does not match the current database"
    totals = [latency for _, latency in actual]
    assert totals == sorted(totals, reverse=True), "CSV is not ordered by latency descending"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
