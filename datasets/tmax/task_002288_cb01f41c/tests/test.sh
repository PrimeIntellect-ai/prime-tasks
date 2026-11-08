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

cat <<'PY_EOF' > /tmp/verify_task.py
import csv
import json
import os
import secrets
import signal
import subprocess
import time
from collections import deque

import requests

BASE_URL = "http://127.0.0.1:8080"
CSV_PATH = "/home/user/transactions.csv"
LOG_PATH = "/home/user/server.log"


def get_json(path):
    response = requests.get(BASE_URL + path, timeout=5)
    assert response.status_code == 200, f"Expected status 200 for {path}, got {response.status_code}"
    return response.json()


def wait_for_service(timeout=30):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(BASE_URL + "/api/deadlocks", timeout=1)
            if response.status_code == 200:
                return
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.25)
    raise AssertionError(f"The HTTP service on 127.0.0.1:8080 did not start: {last_error}")


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if int(local.rsplit(":", 1)[1], 16) == 8080 and state == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    result = set()
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
                    result.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return result


def process_launch_info(pid):
    exe = os.readlink(f"/proc/{pid}/exe")
    cwd = os.readlink(f"/proc/{pid}/cwd")
    with open(f"/proc/{pid}/cmdline", "rb") as handle:
        argv = [part.decode(errors="surrogateescape") for part in handle.read().split(b"\0") if part]
    with open(f"/proc/{pid}/environ", "rb") as handle:
        env_items = [part for part in handle.read().split(b"\0") if part]
    env = {}
    for item in env_items:
        key, sep, value = item.partition(b"=")
        if sep:
            env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    assert argv, "Could not determine the server command line"
    return exe, cwd, argv, env


def stop_listener():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline and listener_pids():
        time.sleep(0.1)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids():
        time.sleep(0.1)
    assert not listener_pids(), "Could not stop the submitted service for the input-variation test"


def start_server(info):
    exe, cwd, argv, env = info
    subprocess.Popen(
        argv,
        executable=exe,
        cwd=cwd,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    wait_for_service()


def expected_analytics(rows):
    nodes = sorted({s for s, _, _ in rows} | {t for _, t, _ in rows})
    adjacency = {node: [] for node in nodes}
    for source, target, _ in rows:
        adjacency[source].append(target)

    deadlocks = []
    for start in nodes:
        stack = list(adjacency[start])
        seen = set()
        cyclic = False
        while stack:
            node = stack.pop()
            if node == start:
                cyclic = True
                break
            if node not in seen:
                seen.add(node)
                stack.extend(adjacency[node])
        if cyclic:
            deadlocks.append(start)

    centrality = [
        {"account": node, "out_degree": len(adjacency[node])}
        for node in sorted(nodes, key=lambda node: (-len(adjacency[node]), node))
    ]

    distances = {}
    for source in nodes:
        dist = {source: 0}
        queue = deque([source])
        while queue:
            node = queue.popleft()
            for nxt in adjacency[node]:
                if nxt not in dist:
                    dist[nxt] = dist[node] + 1
                    queue.append(nxt)
        distances[source] = dist
    return nodes, adjacency, deadlocks, centrality, distances


def verify_dynamic_api(rows):
    nodes, adjacency, deadlocks, centrality, distances = expected_analytics(rows)

    assert get_json("/api/deadlocks") == deadlocks

    for limit in (1, 2, 3, len(nodes), len(nodes) + 3):
        actual = get_json(f"/api/centrality?limit={limit}")
        assert actual == centrality[:limit], f"Incorrect centrality result for limit={limit}: {actual}"

    edges = {(source, target) for source, target, _ in rows}
    for source in nodes:
        for target in nodes:
            path = get_json(f"/api/path?src={source}&dst={target}")
            distance = distances[source].get(target)
            if distance is None:
                assert path == [], f"Expected no path from {source} to {target}, got {path}"
            else:
                assert isinstance(path, list), f"Path response is not an array: {path}"
                assert path[0] == source and path[-1] == target, f"Wrong path endpoints: {path}"
                assert len(path) == distance + 1, f"Path is not shortest from {source} to {target}: {path}"
                assert all(isinstance(node, int) for node in path), f"Path contains non-integer IDs: {path}"
                assert all((a, b) in edges for a, b in zip(path, path[1:])), f"Path uses a nonexistent edge: {path}"

    time.sleep(0.5)
    with open(LOG_PATH, errors="replace") as handle:
        log = handle.read()
    assert log.count("/api/deadlocks") >= 2, "server.log did not record every deadlocks request"
    assert log.count("/api/centrality") >= 5, "server.log did not record every centrality request"
    assert log.count("/api/path") >= len(nodes) * len(nodes), "server.log did not record every path request"


def main():
    wait_for_service()

    # Preserve the original verifier's existence and fixed-response assertions.
    assert os.path.exists(CSV_PATH), f"Expected CSV file {CSV_PATH} does not exist"
    assert os.path.isfile(CSV_PATH), f"{CSV_PATH} is not a file"
    assert os.path.exists(LOG_PATH), f"Expected log file {LOG_PATH} does not exist"
    assert os.path.isfile(LOG_PATH), f"{LOG_PATH} is not a file"

    assert get_json("/api/deadlocks") == [101, 102, 103, 104, 105, 106]
    assert get_json("/api/centrality?limit=3") == [
        {"account": 101, "out_degree": 2},
        {"account": 102, "out_degree": 1},
        {"account": 103, "out_degree": 1},
    ]
    assert get_json("/api/path?src=102&dst=106") == [102, 103, 101, 104, 105, 106]

    with open(CSV_PATH, newline="") as handle:
        reader = csv.reader(handle)
        csv_data = list(reader)
    assert csv_data == [
        ["source_account", "target_account", "amount"],
        ["101", "102", "500"],
        ["102", "103", "300"],
        ["103", "101", "200"],
        ["101", "104", "1000"],
        ["104", "105", "400"],
        ["105", "106", "50"],
        ["106", "104", "10"],
    ], f"transactions.csv does not match the transactions dictated in the audio: {csv_data}"

    pids = listener_pids()
    assert pids, "No process owns the listening socket on port 8080"
    pid = min(pids)
    launch_info = process_launch_info(pid)
    exe = launch_info[0]
    with open(exe, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", "The HTTP listener is not a native compiled executable"

    c_sources = []
    for root in ("/home/user", "/app", "/root", "/tmp"):
        if not os.path.isdir(root):
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".cache", ".git", "__pycache__"}]
            for filename in files:
                if filename.endswith(".c"):
                    path = os.path.join(directory, filename)
                    try:
                        if os.path.getsize(path) > 0:
                            c_sources.append(path)
                    except OSError:
                        pass
    assert c_sources, "No C source file for the submitted graph service was found"

    with open(CSV_PATH, "rb") as handle:
        original_csv = handle.read()

    # Use unpredictable IDs and a different graph, then restart the submitted artifact.
    ids = []
    while len(ids) < 8:
        candidate = 10000 + secrets.randbelow(800000)
        if candidate not in ids:
            ids.append(candidate)
    a, b, c, d, e, f, g, h = ids
    dynamic_rows = [
        (a, b, 11), (b, c, 12), (c, a, 13),
        (a, d, 14), (a, e, 15), (d, e, 16),
        (e, f, 17), (f, e, 18), (g, h, 19),
    ]

    dynamic_process_started = False
    try:
        stop_listener()
        with open(CSV_PATH, "w", newline="") as handle:
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(["source_account", "target_account", "amount"])
            writer.writerows(dynamic_rows)
        with open(LOG_PATH, "w"):
            pass
        start_server(launch_info)
        dynamic_process_started = True
        verify_dynamic_api(dynamic_rows)
    finally:
        try:
            if listener_pids():
                stop_listener()
        finally:
            with open(CSV_PATH, "wb") as handle:
                handle.write(original_csv)
        if dynamic_process_started:
            try:
                start_server(launch_info)
            except Exception:
                pass


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
