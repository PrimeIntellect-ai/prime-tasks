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
import json
import os
import secrets
import signal
import socket
import subprocess
import tempfile
import time

import pytest
import requests

URL = "http://127.0.0.1:9090/query"
AUTH = {"Authorization": "Bearer sc-analytics-2024"}
NODES_PATH = "/home/user/data/nodes.csv"
EDGES_PATH = "/home/user/data/edges.csv"


def listener_pid():
    inode = None
    with open("/proc/net/tcp", "r") as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            local_address = fields[1]
            state = fields[3]
            if local_address.endswith(":2382") and state == "0A":
                inode = fields[9]
                break
    if inode is None:
        return None

    target = "socket:[%s]" % inode
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = "/proc/%s/fd" % entry
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) == target:
                        return int(entry)
                except OSError:
                    pass
        except OSError:
            pass
    return None


def wait_for_listener(timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        pid = listener_pid()
        if pid is not None:
            try:
                with socket.create_connection(("127.0.0.1", 9090), timeout=0.5):
                    return pid
            except OSError:
                pass
        time.sleep(0.1)
    raise AssertionError("Service did not bind to 127.0.0.1:9090")


def stop_listener():
    pid = listener_pid()
    if pid is None:
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.time() + 3
    while time.time() < deadline and listener_pid() is not None:
        time.sleep(0.1)
    pid = listener_pid()
    if pid is not None:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pid() is not None:
        time.sleep(0.1)


def capture_service_command(pid):
    exe = os.readlink("/proc/%d/exe" % pid)
    with open("/proc/%d/cmdline" % pid, "rb") as f:
        raw_args = [x for x in f.read().split(b"\0") if x]
    args = [x.decode("utf-8", "surrogateescape") for x in raw_args]
    assert args, "Could not determine the service command line"
    args[0] = exe
    cwd = os.readlink("/proc/%d/cwd" % pid)
    env = {}
    with open("/proc/%d/environ" % pid, "rb") as f:
        for item in f.read().split(b"\0"):
            if b"=" in item:
                key, value = item.split(b"=", 1)
                env[key.decode("utf-8", "surrogateescape")] = value.decode("utf-8", "surrogateescape")
    return args, cwd, env


def launch_service(command):
    args, cwd, env = command
    log = open("/home/user/service.log", "ab", buffering=0)
    proc = subprocess.Popen(args, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                            stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        wait_for_listener()
    except Exception:
        proc.poll()
        log.close()
        raise
    return proc, log


def test_vendored_engine_bug_fixed():
    recursion_file = "/app/vendored/graph-engine-0.4.2/src/recursion.rs"
    assert os.path.isfile(recursion_file), f"File {recursion_file} is missing."

    with open(recursion_file, "r") as f:
        content = f.read()
        assert "panic!(" not in content, "The panic statement in recursion.rs was not removed."

    with tempfile.TemporaryDirectory() as td:
        with open(os.path.join(td, "Cargo.toml"), "w") as f:
            f.write('''[package]\nname = "engine-verifier"\nversion = "0.1.0"\nedition = "2021"\n\n[dependencies]\ngraph-engine = { path = "/app/vendored/graph-engine-0.4.2" }\n''')
        os.mkdir(os.path.join(td, "src"))
        with open(os.path.join(td, "src", "main.rs"), "w") as f:
            f.write("fn main() { for depth in [0u32, 1, 2, 5, 25] { graph_engine::recursion::execute_recursive(depth); } }\n")
        result = subprocess.run(["cargo", "run", "--offline", "--quiet"], cwd=td,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, timeout=60)
        assert result.returncode == 0, "The vendored recursive engine still fails when executed:\n" + result.stderr


def test_service_unauthorized():
    payload = {"start_node": "root", "max_depth": 5}
    try:
        response = requests.post(URL, json=payload, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running or not reachable at 127.0.0.1:9090")
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"

    for value in ["Bearer wrong", "bearer sc-analytics-2024", "sc-analytics-2024", "Bearer sc-analytics-2024 "]:
        response = requests.post(URL, json=payload, headers={"Authorization": value}, timeout=5)
        assert response.status_code == 401, f"Invalid Authorization value {value!r} was accepted"


def test_service_authorized_query():
    payload = {"start_node": "root", "max_depth": 5}
    try:
        response = requests.post(URL, json=payload, headers=AUTH, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Service is not running or not reachable at 127.0.0.1:9090")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert "result" in data, "Response JSON missing 'result' key"
    assert data["result"] == 450, f"Expected result 450, got {data['result']}"


def test_service_loads_csv_and_handles_dynamic_nodes_and_depths():
    original_pid = wait_for_listener()
    command = capture_service_command(original_pid)
    with open(NODES_PATH, "rb") as f:
        original_nodes = f.read()
    with open(EDGES_PATH, "rb") as f:
        original_edges = f.read()

    suffix = secrets.token_hex(6)
    ids = ["verify_%s_%s" % (suffix, name) for name in ["root", "a", "b", "c", "d", "e", "isolated"]]
    root, a, b, c, d, e, isolated = ids
    weights = [secrets.randbelow(80) + 11 for _ in range(5)]
    edges = [
        (root, a, weights[0]),
        (root, b, weights[1]),
        (a, c, weights[2]),
        (c, d, weights[3]),
        (b, e, weights[4]),
    ]

    def expected(start, max_depth):
        total = 0
        frontier = [start]
        for _ in range(max_depth):
            next_frontier = []
            for parent in frontier:
                for edge_parent, child, weight in edges:
                    if edge_parent == parent:
                        total += weight
                        next_frontier.append(child)
            frontier = next_frontier
        return total

    dynamic_proc = None
    dynamic_log = None
    try:
        stop_listener()
        with open(NODES_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "name", "type"])
            for node_id in ids:
                writer.writerow([node_id, "Generated " + node_id, "test"])
        with open(EDGES_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["parent_id", "child_id", "weight"])
            writer.writerows(edges)

        dynamic_proc, dynamic_log = launch_service(command)

        cases = [(node_id, depth) for node_id in ids for depth in [1, 2, 3, 4, 7]]
        for start, depth in cases:
            response = requests.post(URL, json={"start_node": start, "max_depth": depth},
                                     headers=AUTH, timeout=5)
            want = expected(start, depth)
            assert response.status_code == 200, (
                f"Query for start_node={start!r}, max_depth={depth} returned "
                f"{response.status_code}: {response.text}"
            )
            try:
                body = response.json()
            except ValueError:
                pytest.fail(f"Dynamic query response is not JSON: {response.text}")
            assert body == {"result": want}, (
                f"For start_node={start!r}, max_depth={depth}, expected "
                f"{{'result': {want}}}, got {body!r}"
            )
    finally:
        stop_listener()
        if dynamic_proc is not None:
            try:
                dynamic_proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                dynamic_proc.kill()
        if dynamic_log is not None:
            dynamic_log.close()
        with open(NODES_PATH, "wb") as f:
            f.write(original_nodes)
        with open(EDGES_PATH, "wb") as f:
            f.write(original_edges)
        launch_service(command)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
