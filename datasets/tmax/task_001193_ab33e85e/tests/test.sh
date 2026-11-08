#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import py_compile
import random
import subprocess

import pytest

AGENT_SCRIPT = "/home/user/run_resolver_v3.py"
LEGACY_DIR = "/home/user/legacy_resolver"
N_RUNS = 200


def expected_resolution(graph):
    """Alphabetical DFS postorder, dropping edges to active nodes."""
    state = {}
    result = []

    def visit(node):
        status = state.get(node, 0)
        if status == 2:
            return
        if status == 1:
            return  # Drop the back-edge that entered an active node.
        state[node] = 1
        for dependency in sorted(graph.get(node, [])):
            visit(dependency)
        state[node] = 2
        result.append(node)

    for node in sorted(graph):
        visit(node)
    return result


def run_json_command(command, graph, timeout=5):
    proc = subprocess.run(
        command,
        input=json.dumps(graph),
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    assert proc.returncode == 0, (
        f"Command failed with exit code {proc.returncode}.\n"
        f"Input: {graph!r}\nStdout: {proc.stdout!r}\nStderr: {proc.stderr!r}"
    )
    assert proc.stdout.strip(), "Command produced no JSON output"
    try:
        value = json.loads(proc.stdout)
    except Exception as exc:
        pytest.fail(f"Stdout is not a single valid JSON value: {proc.stdout!r}: {exc}")
    assert isinstance(value, list), f"Expected a JSON list, got {type(value).__name__}"
    return value


def run_agent(graph, timeout=5):
    return run_json_command([AGENT_SCRIPT], graph, timeout)


def run_legacy_resolver(graph, timeout=5):
    probe = r'''import json, sys
sys.path.insert(0, "/home/user/legacy_resolver")
import resolver
graph = json.load(sys.stdin)
result = resolver.resolve(graph)
print(json.dumps(result))
'''
    return run_json_command(["python3", "-c", probe], graph, timeout)


def test_agent_executable_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script at {AGENT_SCRIPT} is not executable"


def test_patch_effect_and_python3_migration():
    required = ["graph.py", "nodes.py", "resolver.py"]
    for filename in required:
        path = os.path.join(LEGACY_DIR, filename)
        assert os.path.isfile(path), f"Missing migrated legacy file: {path}"
        py_compile.compile(path, doraise=True)

    nodes_path = os.path.join(LEGACY_DIR, "nodes.py")
    with open(nodes_path, "r", encoding="utf-8") as handle:
        nodes_tree = ast.parse(handle.read(), filename=nodes_path)

    imported = set()
    for node in ast.walk(nodes_tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split(".")[0])
    assert "types" in imported, "The recovered nodes.py patch was not applied (missing import types)"
    assert "graph" not in imported, "The recovered patch must remove nodes.py's circular import of graph"

    probe = r'''import sys
sys.path.insert(0, "/home/user/legacy_resolver")
import graph, nodes, resolver
assert graph.Graph() is not None
assert nodes.Node("A").name == "A"
assert callable(resolver.resolve)
'''
    proc = subprocess.run(["python3", "-c", probe], text=True, capture_output=True, timeout=5)
    assert proc.returncode == 0, (
        "Migrated legacy modules cannot be imported and instantiated under Python 3.\n"
        f"Stdout: {proc.stdout!r}\nStderr: {proc.stderr!r}"
    )


def test_cli_uses_migrated_resolver_architecture():
    with open(AGENT_SCRIPT, "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read(), filename=AGENT_SCRIPT)
    imports_resolver = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imports_resolver |= any(alias.name.split(".")[-1] == "resolver" for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ""
            imports_resolver |= module.split(".")[-1] == "resolver"
            imports_resolver |= any(alias.name == "resolver" for alias in node.names)
    assert imports_resolver, "The final CLI must use the migrated resolver architecture"


def test_known_traversal_and_cycle_cases():
    cases = [
        {},
        {"A": []},
        {"A": ["B", "C"], "B": ["C", "A"], "C": []},
        {"A": ["B"], "B": ["A"]},
        {"A": ["C", "B"], "B": ["D"], "C": ["D"], "D": []},
        {"A": ["B"], "B": [], "C": ["D"], "D": ["C"]},
    ]
    for graph in cases:
        expected = expected_resolution(graph)
        assert run_agent(graph) == expected
        assert run_legacy_resolver(graph) == expected


def generate_graph(rng, num_nodes, edge_probability):
    nodes = [f"N{i:03d}" for i in range(num_nodes)]
    graph = {node: [] for node in nodes}

    # Make every node reachable from the alphabetically first node while still
    # retaining random cycles and cross-edges.
    graph[nodes[0]].extend(nodes[1:])
    for source in nodes:
        for target in nodes:
            if source != target and rng.random() < edge_probability:
                graph[source].append(target)
        graph[source] = sorted(set(graph[source]))
    return graph


def test_fuzz_equivalence_to_derived_algorithm():
    rng = random.Random(42)
    for run in range(N_RUNS):
        graph = generate_graph(rng, rng.randint(5, 50), 0.3)
        expected = expected_resolution(graph)
        actual = run_agent(graph)
        assert actual == expected, (
            f"Traversal mismatch on fuzz run {run + 1}/{N_RUNS}.\n"
            f"Input: {json.dumps(graph, sort_keys=True)}\n"
            f"Expected: {expected!r}\nGot: {actual!r}"
        )


def test_large_graph_runs_quickly():
    size = 600
    graph = {f"N{i:04d}": ([f"N{i + 1:04d}"] if i + 1 < size else []) for i in range(size)}
    assert run_agent(graph, timeout=5) == expected_resolution(graph)
PYTEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
