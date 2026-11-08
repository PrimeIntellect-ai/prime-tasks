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
import heapq
import json
import math
import os
import random
import signal
import sqlite3
import subprocess
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
GRAPH_PATH = "/app/graph.json"
DB_PATH = "/app/metadata.db"
EXPECTED_ACTIVITIES = {0: 0, 1: 128, 2: 255, 3: 102, 4: 191}


def get_json(path, params):
    try:
        response = requests.get(BASE_URL + path, params=params, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to the HTTP server at {BASE_URL}: {exc}")
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")


def listening_pids():
    inodes = set()
    for netfile in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(netfile) as fh:
                next(fh)
                for line in fh:
                    fields = line.split()
                    if fields[3] == "0A" and int(fields[1].split(":")[1], 16) == 8080:
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
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def capture_server():
    pids = listening_pids()
    assert pids, "No process is listening on port 8080"
    pid = min(pids)

    with open(f"/proc/{pid}/exe", "rb") as fh:
        assert fh.read(4) == b"\x7fELF", "The HTTP service is not a compiled native executable"

    exe = os.path.realpath(f"/proc/{pid}/exe")
    assert os.path.exists(exe), "The running service executable is no longer available"
    with open(f"/proc/{pid}/cmdline", "rb") as fh:
        cmdline = [x.decode(errors="surrogateescape") for x in fh.read().split(b"\0") if x]
    assert cmdline, "Could not determine the service command line"
    forbidden = {"python", "python3", "node", "ruby", "perl", "bash", "sh", "java"}
    assert os.path.basename(exe).lower() not in forbidden, "The HTTP API must be a compiled C++ service"

    with open(f"/proc/{pid}/maps", errors="ignore") as fh:
        maps = fh.read()
    cpp_runtime = "libstdc++" in maps or "libc++" in maps
    if not cpp_runtime:
        with open(exe, "rb") as fh:
            binary = fh.read()
        cpp_runtime = any(marker in binary for marker in (b"GLIBCXX_", b"CXXABI_", b"_ZSt"))
    assert cpp_runtime, "The running HTTP service does not appear to be a C++ executable"

    cwd = os.readlink(f"/proc/{pid}/cwd")
    args = [exe] + cmdline[1:]
    return pid, args, cwd


def stop_server(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(30):
        if not os.path.exists(f"/proc/{pid}"):
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    time.sleep(0.2)


def start_server(args, cwd):
    proc = subprocess.Popen(
        args,
        cwd=cwd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 10
    while time.time() < deadline:
        if listening_pids():
            try:
                requests.get(BASE_URL + "/path", timeout=0.5)
            except requests.RequestException:
                time.sleep(0.1)
                continue
            return proc
        if proc.poll() is not None:
            pytest.fail(f"The C++ service exited during restart with status {proc.returncode}")
        time.sleep(0.1)
    pytest.fail("The C++ service did not resume listening on port 8080")


def shortest_cost(graph, start, end):
    distances = {start: 0}
    queue = [(0, start)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances[node]:
            continue
        if node == end:
            return distance
        for neighbor, weight in graph[node].items():
            candidate = distance + weight
            if candidate < distances.get(neighbor, float("inf")):
                distances[neighbor] = candidate
                heapq.heappush(queue, (candidate, neighbor))
    return float("inf")


def assert_valid_path_response(graph, start, end, data):
    assert "path" in data, "Response JSON missing 'path' key"
    assert "cost" in data, "Response JSON missing 'cost' key"
    path = data["path"]
    assert isinstance(path, list) and path, f"Invalid path value: {path!r}"
    assert path[0] == start and path[-1] == end, f"Path has wrong endpoints: {path}"
    actual_cost = 0
    for left, right in zip(path, path[1:]):
        assert right in graph.get(left, {}), f"Path uses nonexistent edge {left}->{right}"
        actual_cost += graph[left][right]
    expected_cost = shortest_cost(graph, start, end)
    assert actual_cost == expected_cost, f"Path {path} costs {actual_cost}, expected {expected_cost}"
    assert float(data["cost"]) == expected_cost, f"Reported cost {data['cost']}, expected {expected_cost}"


def test_db_epochs_populated():
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute(
        "SELECT epoch_index, activity_level FROM epochs WHERE subject_id=1 ORDER BY epoch_index ASC"
    ).fetchall()
    conn.close()

    assert len(rows) >= 5, f"Expected at least 5 epochs in the database, found {len(rows)}"
    seen = set()
    for epoch_index, activity_level in rows:
        if epoch_index in EXPECTED_ACTIVITIES:
            seen.add(epoch_index)
            expected = EXPECTED_ACTIVITIES[epoch_index]
            assert math.isclose(activity_level, expected, abs_tol=15), (
                f"Epoch {epoch_index} activity level {activity_level} is not close to expected {expected}"
            )
    assert seen == set(EXPECTED_ACTIVITIES), f"Missing required epoch rows: {set(EXPECTED_ACTIVITIES) - seen}"


def test_api_path_a_to_d():
    data = get_json("/path", {"start": "A", "end": "D"})
    assert "path" in data, "Response JSON missing 'path' key"
    assert "cost" in data, "Response JSON missing 'cost' key"
    assert data["path"] == ["A", "C", "B", "D"], f"Unexpected path: {data['path']}"
    assert data["cost"] == 9, f"Expected cost 9, got {data['cost']}"


def test_api_path_c_to_a():
    data = get_json("/path", {"start": "C", "end": "A"})
    assert data["path"] == ["C", "E", "A"], f"Unexpected path: {data['path']}"
    assert data["cost"] == 9, f"Expected cost 9, got {data['cost']}"


def test_api_activity():
    for epoch, expected in EXPECTED_ACTIVITIES.items():
        data = get_json("/activity", {"epoch": epoch})
        assert "epoch" in data, "Response JSON missing 'epoch' key"
        assert "activity" in data, "Response JSON missing 'activity' key"
        assert int(data["epoch"]) == epoch, f"Expected epoch {epoch}, got {data['epoch']}"
        assert math.isclose(float(data["activity"]), expected, abs_tol=15), (
            f"Expected activity for epoch {epoch} near {expected}, got {data['activity']}"
        )


def test_dynamic_graph_and_database_queries():
    original_graph = open(GRAPH_PATH, "rb").read()
    old_pid, args, cwd = capture_server()
    dynamic_epoch = random.SystemRandom().randrange(100000, 2000000000)
    dynamic_activity = random.SystemRandom().randrange(1, 255)
    dynamic_pid = None

    nodes = ["A", "B", "C", "D", "E"]
    rng = random.SystemRandom()
    graph = {
        node: {other: rng.randrange(1, 1000) for other in nodes if other != node}
        for node in nodes
    }

    try:
        with open(GRAPH_PATH, "w") as fh:
            json.dump(graph, fh)

        stop_server(old_pid)
        start_server(args, cwd)
        current = listening_pids()
        assert current, "Restarted service is not listening"
        dynamic_pid = min(current)

        for start in nodes:
            for end in nodes:
                data = get_json("/path", {"start": start, "end": end})
                assert_valid_path_response(graph, start, end, data)

        conn = sqlite3.connect(DB_PATH)
        conn.execute(
            "DELETE FROM epochs WHERE subject_id=? AND epoch_index=?", (1, dynamic_epoch)
        )
        conn.execute(
            "INSERT INTO epochs(subject_id, epoch_index, activity_level) VALUES (?, ?, ?)",
            (1, dynamic_epoch, dynamic_activity),
        )
        conn.commit()
        conn.close()

        data = get_json("/activity", {"epoch": dynamic_epoch})
        assert int(data["epoch"]) == dynamic_epoch
        assert int(data["activity"]) == dynamic_activity, (
            "The activity endpoint did not query the newly inserted SQLite row"
        )
    finally:
        conn = sqlite3.connect(DB_PATH)
        conn.execute(
            "DELETE FROM epochs WHERE subject_id=? AND epoch_index=?", (1, dynamic_epoch)
        )
        conn.commit()
        conn.close()
        with open(GRAPH_PATH, "wb") as fh:
            fh.write(original_graph)
        if dynamic_pid is not None:
            stop_server(dynamic_pid)
        else:
            for pid in listening_pids():
                stop_server(pid)
        start_server(args, cwd)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
