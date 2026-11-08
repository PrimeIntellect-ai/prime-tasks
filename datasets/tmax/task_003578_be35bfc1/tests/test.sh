#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import io
import json
import os
import random
import sqlite3
import subprocess
import sys

import networkx as nx

AGENT_SCRIPT = "/home/user/graph_query.py"
VENDORED_ROOT = "/app/networkx-3.1"
TARGET_FILE = "/app/networkx-3.1/networkx/algorithms/shortest_paths/unweighted.py"
DB_PATH = "/home/user/data/network.db"


def test_graph_query_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), "Agent script /home/user/graph_query.py does not exist."


def test_perturbation_fixed():
    assert os.path.isfile(TARGET_FILE), f"Target file not found at {TARGET_FILE}"

    with open(TARGET_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    tree = ast.parse(content, filename=TARGET_FILE)
    target_function = next(
        (
            node
            for node in tree.body
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
            and node.name == "bidirectional_shortest_path"
        ),
        None,
    )
    assert target_function is not None, "bidirectional_shortest_path is missing from the vendored source."

    for node in ast.walk(target_function):
        if not isinstance(node, ast.Raise) or node.exc is None:
            continue
        for child in ast.walk(node.exc):
            if isinstance(child, ast.Constant) and child.value == "DBA Optimization Required":
                raise AssertionError("The deliberate exception remains active in bidirectional_shortest_path.")

    probe = subprocess.run(
        [
            "python3",
            "-c",
            "import networkx as nx; "
            "assert nx.__file__.startswith('/app/networkx-3.1/'), nx.__file__; "
            "G=nx.Graph(); G.add_edges_from([(1,2),(2,3)]); "
            "assert nx.shortest_path(G,1,3)==[1,2,3]",
        ],
        cwd="/tmp",
        env={**os.environ, "PYTHONPATH": VENDORED_ROOT},
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert probe.returncode == 0, f"Vendored unweighted shortest path is still broken: {probe.stderr}"


def test_agent_uses_vendored_networkx():
    wrapper = r'''
import io
import json
import runpy
import sys

sys.stdin = io.StringIO("1,1\n")
captured = io.StringIO()
real_stdout = sys.stdout
sys.stdout = captured
exit_code = 0
try:
    runpy.run_path("/home/user/graph_query.py", run_name="__main__")
except SystemExit as exc:
    if exc.code not in (None, 0):
        exit_code = exc.code
finally:
    sys.stdout = real_stdout

module = sys.modules.get("networkx")
print(json.dumps({
    "exit_code": exit_code,
    "networkx_file": getattr(module, "__file__", None),
    "agent_output": captured.getvalue(),
}))
'''
    proc = subprocess.run(
        ["python3", "-c", wrapper],
        cwd="/tmp",
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert proc.returncode == 0, f"Could not execute agent script: {proc.stderr}"
    try:
        result = json.loads(proc.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError) as exc:
        raise AssertionError(f"Could not inspect agent's NetworkX import: {proc.stdout!r}") from exc
    assert result["exit_code"] == 0, f"Agent exited with status {result['exit_code']}"
    module_path = result["networkx_file"]
    assert module_path is not None, "Agent script did not import networkx."
    assert os.path.realpath(module_path).startswith(os.path.realpath(VENDORED_ROOT) + os.sep), (
        f"Agent imported NetworkX from {module_path!r}, not from {VENDORED_ROOT}."
    )


def calculate_expected(inputs):
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT id, weight FROM nodes WHERE is_active=1")
        active_nodes = {node_id: weight for node_id, weight in cursor.fetchall()}

        cursor.execute("SELECT source, target FROM edges WHERE is_active=1")
        active_edges = [
            (source, target)
            for source, target in cursor.fetchall()
            if source in active_nodes and target in active_nodes
        ]
    finally:
        conn.close()

    graph = nx.Graph()
    for node_id, weight in active_nodes.items():
        graph.add_node(node_id, weight=weight)
    graph.add_edges_from(active_edges)

    output = []
    for item in inputs:
        start, end = map(int, item.split(","))
        if start not in graph or end not in graph:
            output.append("-1,-1")
            continue
        try:
            path = nx.shortest_path(graph, source=start, target=end)
            output.append(f"{len(path) - 1},{sum(graph.nodes[n]['weight'] for n in path)}")
        except (nx.NetworkXNoPath, nx.NodeNotFound):
            output.append("-1,-1")
    return output


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"

    random.seed(42)
    inputs = []
    for _ in range(500):
        start = random.randint(1, 1000)
        end = random.randint(1, 1000)
        inputs.append(f"{start},{end}")

    input_str = "\n".join(inputs) + "\n"
    expected_output = calculate_expected(inputs)

    agent_proc = subprocess.run(
        ["python3", AGENT_SCRIPT],
        input=input_str,
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert agent_proc.returncode == 0, f"Agent script failed: {agent_proc.stderr}"
    agent_output = agent_proc.stdout.strip().split("\n")

    assert len(expected_output) == len(agent_output), "Agent script output line count does not match oracle."

    for i, (in_line, expected_line, agent_line) in enumerate(zip(inputs, expected_output, agent_output)):
        assert expected_line == agent_line, (
            f"Mismatch on input '{in_line}' (line {i+1}). "
            f"Expected '{expected_line}', got '{agent_line}'."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
