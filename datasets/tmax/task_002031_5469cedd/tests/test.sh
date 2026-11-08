#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import stat
import subprocess
import tempfile

import pytest

HOME = "/home/user"
SOURCE = f"{HOME}/deadlock_detector.cpp"
DETECTOR = f"{HOME}/detector"
PROCESS = f"{HOME}/process.sh"
GRAPH = f"{HOME}/transactions.graph"
REPORT = f"{HOME}/deadlock_report.json"

ORIGINAL_GRAPH = """Tx10 :ACQUIRED Lock1
Tx11 :ACQUIRED Lock2
Tx12 :ACQUIRED Lock3
Tx13 :ACQUIRED Lock4
Tx10 :WAIT_FOR Tx11
Tx11 :KNOWS Tx15
Tx11 :WAIT_FOR Tx12
Tx12 :WAIT_FOR Tx13
Tx13 :WAIT_FOR Tx11
Tx99 :WAIT_FOR Tx100
Tx100 :WAIT_FOR Tx101
"""


def run(cmd, **kwargs):
    return subprocess.run(cmd, timeout=15, check=True, **kwargs)


def expected_cycle_nodes(edges):
    nodes = sorted({n for edge in edges for n in edge})
    adjacency = {n: [] for n in nodes}
    reverse = {n: [] for n in nodes}
    for source, target in edges:
        adjacency[source].append(target)
        reverse[target].append(source)

    seen = set()
    order = []

    def visit(node):
        if node in seen:
            return
        seen.add(node)
        for nxt in adjacency[node]:
            visit(nxt)
        order.append(node)

    for node in nodes:
        visit(node)

    seen.clear()
    components = []

    def collect(node, component):
        if node in seen:
            return
        seen.add(node)
        component.append(node)
        for nxt in reverse[node]:
            collect(nxt, component)

    for node in reversed(order):
        if node not in seen:
            component = []
            collect(node, component)
            components.append(component)

    self_loops = {source for source, target in edges if source == target}
    result = []
    for component in components:
        if len(component) > 1 or component[0] in self_loops:
            result.extend(component)
    return sorted(result)


def assert_detector_result(executable, edges):
    payload = "".join(f"{source},{target}\n" for source, target in edges)
    completed = run(
        [executable],
        input=payload,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        data = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        pytest.fail(f"Detector output is not valid JSON: {exc}; output={completed.stdout!r}")

    expected = expected_cycle_nodes(edges)
    assert set(data.keys()) == {"deadlock_detected", "deadlocked_transactions"}
    assert data["deadlock_detected"] is bool(expected)
    assert isinstance(data["deadlocked_transactions"], list)
    assert all(isinstance(node, str) for node in data["deadlocked_transactions"])
    assert data["deadlocked_transactions"] == expected


def randomized_cases():
    prefix = "N" + secrets.token_hex(8)
    n = [f"{prefix}_{i}" for i in range(12)]
    return [
        [],
        [(n[0], n[1]), (n[1], n[2]), (n[2], n[3])],
        [(n[0], n[1]), (n[1], n[2]), (n[2], n[0]), (n[2], n[3]),
         (n[4], n[5]), (n[5], n[4]), (n[6], n[7])],
        [(n[0], n[0]), (n[1], n[2]), (n[2], n[3]), (n[3], n[1]),
         (n[4], n[5]), (n[5], n[6]), (n[6], n[4]), (n[7], n[8])],
    ]


def validate_report(path, expected):
    with open(path, "r") as handle:
        data = json.load(handle)
    assert set(data.keys()) == {"deadlock_detected", "deadlocked_transactions"}
    assert data["deadlock_detected"] is bool(expected)
    assert data["deadlocked_transactions"] == expected


def test_cpp_source_exists():
    path = "/home/user/deadlock_detector.cpp"
    assert os.path.exists(path), f"C++ source file {path} is missing."
    assert os.path.isfile(path), f"Path {path} is not a file."


def test_compiled_detector_exists_and_executable():
    path = "/home/user/detector"
    assert os.path.exists(path), f"Compiled executable {path} is missing."
    assert os.path.isfile(path), f"Path {path} is not a file."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."
    with open(path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", f"File {path} is not a compiled executable."


def test_process_sh_exists_and_executable():
    path = "/home/user/process.sh"
    assert os.path.exists(path), f"Bash script {path} is missing."
    assert os.path.isfile(path), f"Path {path} is not a file."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."


def test_deadlock_report_json():
    with open(GRAPH, "w") as handle:
        handle.write(ORIGINAL_GRAPH)
    run([PROCESS], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    path = "/home/user/deadlock_report.json"
    assert os.path.exists(path), f"Report file {path} is missing."
    assert os.path.isfile(path), f"Path {path} is not a file."

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {path} does not contain valid JSON."

    assert "deadlock_detected" in data, "Key 'deadlock_detected' missing from JSON."
    assert data["deadlock_detected"] is True, "Expected 'deadlock_detected' to be true."

    assert "deadlocked_transactions" in data, "Key 'deadlocked_transactions' missing from JSON."
    txs = data["deadlocked_transactions"]
    assert isinstance(txs, list), "'deadlocked_transactions' should be a list."

    expected_txs = ["Tx11", "Tx12", "Tx13"]
    assert sorted(txs) == expected_txs, f"Expected deadlocked_transactions to be {expected_txs}, but got {sorted(txs)}."


def test_source_compiles_and_both_binaries_detect_general_cycles():
    with tempfile.TemporaryDirectory() as directory:
        rebuilt = os.path.join(directory, "rebuilt_detector")
        run(
            ["g++", "-std=c++17", "-O2", SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        for edges in randomized_cases():
            assert_detector_result(rebuilt, edges)
            assert_detector_result(DETECTOR, edges)


def test_process_extracts_wait_for_edges_and_pipes_them_to_detector():
    token = secrets.token_hex(8)
    a, b, c, d = [f"Probe_{token}_{i}" for i in range(4)]
    graph_text = (
        f"{a} :ACQUIRED Lock_{token}\n"
        f"{a} :WAIT_FOR {b}\n"
        f"{b} :KNOWS {c}\n"
        f"{b} :WAIT_FOR {c}\n"
        f"{c} :RELEASED Lock_{token}\n"
        f"{d} :WAIT_FOR {d}\n"
    )
    expected_input = f"{a},{b}\n{b},{c}\n{d},{d}\n"
    probe_log = f"/tmp/probe_input_{token}"
    backup = f"/tmp/detector_backup_{token}"
    probe_json = {"deadlock_detected": False, "deadlocked_transactions": []}

    os.replace(DETECTOR, backup)
    try:
        with open(DETECTOR, "w") as handle:
            handle.write("#!/bin/sh\n")
            handle.write(f"cat > {probe_log!r}\n")
            handle.write("printf '%s\\n' '{\"deadlock_detected\":false,\"deadlocked_transactions\":[]}'\n")
        os.chmod(DETECTOR, 0o755)
        with open(GRAPH, "w") as handle:
            handle.write(graph_text)

        run([PROCESS], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        with open(probe_log, "r") as handle:
            assert handle.read() == expected_input
        with open(REPORT, "r") as handle:
            assert json.load(handle) == probe_json
    finally:
        if os.path.exists(DETECTOR):
            os.remove(DETECTOR)
        os.replace(backup, DETECTOR)
        if os.path.exists(probe_log):
            os.remove(probe_log)
        with open(GRAPH, "w") as handle:
            handle.write(ORIGINAL_GRAPH)


def test_process_end_to_end_on_unseen_graph():
    token = secrets.token_hex(8)
    nodes = [f"Txn_{token}_{i}" for i in range(10)]
    wait_edges = [
        (nodes[0], nodes[1]), (nodes[1], nodes[2]), (nodes[2], nodes[0]),
        (nodes[2], nodes[3]), (nodes[4], nodes[5]), (nodes[5], nodes[4]),
        (nodes[6], nodes[7]), (nodes[8], nodes[8]),
    ]
    lines = [
        f"{nodes[0]} :ACQUIRED Lock_{token}",
        f"{nodes[3]} :KNOWS {nodes[0]}",
        f"{nodes[9]} :RELEASED Lock_{token}",
    ]
    lines.extend(f"{source} :WAIT_FOR {target}" for source, target in wait_edges)

    try:
        with open(GRAPH, "w") as handle:
            handle.write("\n".join(lines) + "\n")
        run([PROCESS], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        validate_report(REPORT, expected_cycle_nodes(wait_edges))
    finally:
        with open(GRAPH, "w") as handle:
            handle.write(ORIGINAL_GRAPH)
        run([PROCESS], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
