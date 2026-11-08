#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import shutil
import signal
import socket
import subprocess
import tempfile
import time
from collections import Counter, defaultdict

import pytest


def derive_expected_edges():
    data_path = "/home/user/data.csv"
    assert os.path.exists(data_path), f"File {data_path} does not exist."

    with open(data_path, newline="") as f:
        rows = list(csv.reader(f))

    assert rows, "data.csv is empty"
    width = len(rows[0])
    assert width >= 2 and all(len(row) == width for row in rows), "data.csv has inconsistent rows"

    employee_columns = []
    for col in range(width):
        try:
            values = [int(row[col]) for row in rows]
        except ValueError:
            continue
        if len(values) == len(set(values)):
            employee_columns.append((col, values))

    candidates = []
    for employee_col, employee_ids in employee_columns:
        employee_set = set(employee_ids)
        for manager_col in range(width):
            if manager_col == employee_col:
                continue
            try:
                manager_ids = [int(row[manager_col]) for row in rows]
            except ValueError:
                continue
            if 0 in manager_ids and all(manager == 0 or manager in employee_set for manager in manager_ids):
                candidates.append((employee_col, manager_col, employee_ids, manager_ids))

    assert len(candidates) == 1, f"Could not uniquely identify employee and manager columns: {[(x[0], x[1]) for x in candidates]}"
    _, _, employee_ids, manager_ids = candidates[0]
    return [(manager, employee) for employee, manager in zip(employee_ids, manager_ids) if manager != 0]


def read_hierarchy():
    hierarchy_path = "/home/user/hierarchy.csv"
    assert os.path.exists(hierarchy_path), f"File {hierarchy_path} does not exist."

    edges = []
    with open(hierarchy_path, newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            assert len(row) == 2, f"Expected exactly 2 columns in hierarchy.csv, got {len(row)}: {row}"
            try:
                edges.append((int(row[0]), int(row[1])))
            except ValueError:
                pytest.fail(f"Values in hierarchy.csv must be integers, got: {row}")
    return edges


def test_hierarchy_csv_exists_and_valid():
    """Check hierarchy.csv format and its exact projection from data.csv."""
    actual = read_hierarchy()
    expected = derive_expected_edges()
    assert Counter(actual) == Counter(expected), f"hierarchy.csv does not match data.csv projection. Expected {expected}, got {actual}"


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        if int(fields[1].rsplit(":", 1)[1], 16) == port:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
    for fd in glob.glob("/proc/[0-9]*/fd/*"):
        try:
            target = os.readlink(fd)
        except OSError:
            continue
        if target.startswith("socket:[") and target[8:-1] in inodes:
            pids.add(int(fd.split("/")[2]))
    return pids


def build_and_start_vendored_server():
    build_dir = tempfile.mkdtemp(prefix="org-server-verifier-")
    for name in ("Makefile", "server.c", "graph.c", "graph.h"):
        src = os.path.join("/app/org-server", name)
        assert os.path.isfile(src), f"Missing vendored source file: {src}"
        shutil.copy2(src, os.path.join(build_dir, name))

    result = subprocess.run(
        ["make", "-B"], cwd=build_dir, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
    )
    assert result.returncode == 0, f"Vendored application does not compile with make:\n{result.stdout}"

    binary = os.path.join(build_dir, "server")
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "Makefile did not produce an executable server"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Makefile output is not a compiled executable"

    for pid in listener_pids(8888):
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

    deadline = time.time() + 3
    while listener_pids(8888) and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids(8888):
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass

    proc = subprocess.Popen(
        [binary], cwd=build_dir, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True
    )
    deadline = time.time() + 3
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"Compiled server exited immediately with status {proc.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", 8888), timeout=0.2):
                return proc
        except OSError:
            time.sleep(0.05)
    pytest.fail("Compiled server is not listening on 127.0.0.1:8888")


def test_server_reports():
    """Check the compiled vendored server returns descendants derived from data.csv."""
    expected_edges = derive_expected_edges()
    assert Counter(read_hierarchy()) == Counter(expected_edges)

    graph = defaultdict(list)
    nodes = set()
    for manager, employee in expected_edges:
        graph[manager].append(employee)
        nodes.add(manager)
        nodes.add(employee)

    def get_all_descendants(node):
        descendants = set()
        stack = [node]
        while stack:
            current = stack.pop()
            for child in graph[current]:
                if child not in descendants:
                    descendants.add(child)
                    stack.append(child)
        return descendants

    proc = build_and_start_vendored_server()
    assert proc.poll() is None

    for node in sorted(nodes):
        expected = get_all_descendants(node)
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(3.0)
            try:
                s.connect(("127.0.0.1", 8888))
            except ConnectionRefusedError:
                pytest.fail("Server is not listening on 127.0.0.1:8888")

            s.sendall(f"REPORTS {node}\n".encode("utf-8"))
            data = b""
            while b"\n" not in data:
                chunk = s.recv(4096)
                if not chunk:
                    break
                data += chunk

        response = data.decode("utf-8").strip()
        if not expected:
            assert response == "", f"Expected empty response for node {node} (no descendants), got '{response}'"
        else:
            assert response != "", f"Expected descendants for node {node}, got empty response"
            try:
                actual_desc = set(map(int, response.split(",")))
            except ValueError:
                pytest.fail(f"Server returned invalid format for node {node}: '{response}'")
            assert actual_desc == expected, f"Descendants mismatch for node {node}. Expected {expected}, got {actual_desc}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
