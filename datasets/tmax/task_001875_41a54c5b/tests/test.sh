#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import os
import random
import shutil
import subprocess
import tempfile

import pytest

WORKSPACE_DIR = "/home/user/sys_debug"
SOLVER_PATH = os.path.join(WORKSPACE_DIR, "solver.py")
GRAPH_DEF_PATH = os.path.join(WORKSPACE_DIR, "graph_def.txt")
LIBGRAPH_PATH = os.path.join(WORKSPACE_DIR, "libgraph.so")
OUTPUT_PATH = os.path.join(WORKSPACE_DIR, "output.log")


def solver_env():
    env = os.environ.copy()
    old = env.get("LD_LIBRARY_PATH", "")
    env["LD_LIBRARY_PATH"] = f"{WORKSPACE_DIR}:{old}"
    return env


def run_solver():
    return subprocess.run(
        ["python3", SOLVER_PATH],
        cwd=WORKSPACE_DIR,
        env=solver_env(),
        capture_output=True,
        text=True,
        timeout=15,
    )


def test_libraries_built():
    """Test if libmatrix.so and libgraph.so have been built."""
    assert os.path.isfile(os.path.join(WORKSPACE_DIR, "libmatrix.so")), "libmatrix.so is missing. Did you run make?"
    assert os.path.isfile(os.path.join(WORKSPACE_DIR, "libgraph.so")), "libgraph.so is missing. Did you run make?"


def test_libgraph_linking():
    """Test if libgraph.so correctly links against libmatrix.so and can be loaded."""
    env = solver_env()
    script = f"""
import ctypes
try:
    ctypes.CDLL('{WORKSPACE_DIR}/libgraph.so')
except Exception:
    import sys
    sys.exit(1)
"""
    result = subprocess.run(["python3", "-c", script], env=env, capture_output=True, text=True)
    assert result.returncode == 0, (
        "Failed to load libgraph.so via ctypes. It might not be correctly linked "
        f"against libmatrix.so. Error: {result.stderr}"
    )


def test_solver_script_exists():
    """Test if the solver.py script was created."""
    assert os.path.isfile(SOLVER_PATH), f"{SOLVER_PATH} does not exist."


def test_solver_executes_on_original_input():
    result = run_solver()
    assert result.returncode == 0, f"solver.py failed: {result.stderr}"


def test_output_log():
    """Test if output.log exists and contains the correct traversal count."""
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} does not exist. Did solver.py run successfully?"
    with open(OUTPUT_PATH, "r") as f:
        content = f.read().strip()
    assert content == "7", f"Expected output.log to contain '7', but got '{content}'."


def _name_tail(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    return None


def test_explicit_ctypes_signatures():
    """The three graph ABI functions must have explicit ctypes signatures."""
    with open(SOLVER_PATH, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=SOLVER_PATH)

    argtypes = {}
    restypes = {}
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Assign, ast.AnnAssign)):
            continue
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        value = node.value
        for target in targets:
            if not isinstance(target, ast.Attribute) or not isinstance(target.value, ast.Attribute):
                continue
            function_name = target.value.attr
            if target.attr == "argtypes" and isinstance(value, (ast.List, ast.Tuple)):
                argtypes[function_name] = [_name_tail(item) for item in value.elts]
            elif target.attr == "restype":
                restypes[function_name] = None if isinstance(value, ast.Constant) and value.value is None else _name_tail(value)

    assert argtypes.get("init_graph") == ["c_int"], "init_graph.argtypes must be [ctypes.c_int]"
    assert restypes.get("init_graph", "missing") is None, "init_graph.restype must be None"
    assert argtypes.get("add_edge") == ["c_int", "c_int"], "add_edge.argtypes must contain two ctypes.c_int values"
    assert restypes.get("add_edge", "missing") is None, "add_edge.restype must be None"
    assert argtypes.get("traverse_and_count") == ["c_int"], "traverse_and_count.argtypes must be [ctypes.c_int]"
    assert restypes.get("traverse_and_count") == "c_int", "traverse_and_count.restype must be ctypes.c_int"


def _expected_reachable(node_count, edges):
    adjacency = [[] for _ in range(node_count)]
    for source, destination in edges:
        adjacency[source].append(destination)
    seen = {0}
    pending = [0]
    while pending:
        current = pending.pop()
        for destination in adjacency[current]:
            if destination not in seen:
                seen.add(destination)
                pending.append(destination)
    return len(seen)


def _graph_text(node_count, edges):
    by_source = {node: [] for node in range(node_count)}
    for source, destination in edges:
        by_source[source].append(destination)
    lines = []
    for node in range(node_count):
        lines.append(f"NODE {node}")
        lines.extend(f"DEPENDS {destination}" for destination in by_source[node])
        lines.append("END")
    return "\n".join(lines) + "\n"


def test_solver_parses_changed_graph_and_computes_result():
    """Run the submitted artifact on a graph whose answer is derived by the test."""
    rng = random.SystemRandom()
    node_count = rng.randrange(9, 15)
    edges = []
    for source in range(node_count):
        for destination in range(node_count):
            if source != destination and rng.randrange(7) == 0:
                edges.append((source, destination))
    # Guarantee both a reachable chain and at least one nontrivial dependency block.
    edges.extend((i, i + 1) for i in range(0, node_count - 2))
    edges = list(dict.fromkeys(edges))
    graph_text = _graph_text(node_count, edges)
    expected = _expected_reachable(node_count, edges)

    original_graph = open(GRAPH_DEF_PATH, "rb").read()
    original_output = open(OUTPUT_PATH, "rb").read() if os.path.exists(OUTPUT_PATH) else None
    try:
        with open(GRAPH_DEF_PATH, "w", encoding="utf-8") as f:
            f.write(graph_text)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        result = run_solver()
        assert result.returncode == 0, f"solver.py failed on a changed graph: {result.stderr}"
        assert os.path.isfile(OUTPUT_PATH), "solver.py did not create output.log"
        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            actual = f.read().strip()
        assert actual == str(expected), f"Expected traversal count {expected}, got {actual!r}"
    finally:
        with open(GRAPH_DEF_PATH, "wb") as f:
            f.write(original_graph)
        if original_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(original_output)


def test_solver_invokes_graph_api_for_parsed_edges():
    """Use an instrumented ABI-compatible library to verify all required FFI calls."""
    rng = random.SystemRandom()
    node_count = rng.randrange(7, 12)
    edges = [(0, 2), (0, 4), (2, 3), (4, 5), (5, 1), (1, node_count - 1)]
    marker_result = rng.randrange(100000, 900000)
    graph_text = _graph_text(node_count, edges)

    original_graph = open(GRAPH_DEF_PATH, "rb").read()
    original_lib = open(LIBGRAPH_PATH, "rb").read()
    original_output = open(OUTPUT_PATH, "rb").read() if os.path.exists(OUTPUT_PATH) else None

    with tempfile.TemporaryDirectory() as tmpdir:
        call_log = os.path.join(tmpdir, "calls.log")
        source_path = os.path.join(tmpdir, "spy.c")
        spy_path = os.path.join(tmpdir, "libgraph.so")
        escaped_log = call_log.replace("\\", "\\\\").replace('"', '\\"')
        source = f'''\n#include <stdio.h>\nstatic void record(const char *kind, int a, int b) {{\n    FILE *f = fopen("{escaped_log}", "a");\n    if (f) {{ fprintf(f, "%s %d %d\\n", kind, a, b); fclose(f); }}\n}}\nvoid init_graph(int n) {{ record("init", n, -1); }}\nvoid add_edge(int from, int to) {{ record("edge", from, to); }}\nint traverse_and_count(int start) {{ record("traverse", start, -1); return {marker_result}; }}\n'''
        with open(source_path, "w", encoding="utf-8") as f:
            f.write(source)
        built = subprocess.run(
            ["gcc", "-shared", "-fPIC", "-o", spy_path, source_path],
            capture_output=True,
            text=True,
        )
        assert built.returncode == 0, f"Could not build test library: {built.stderr}"

        try:
            with open(GRAPH_DEF_PATH, "w", encoding="utf-8") as f:
                f.write(graph_text)
            shutil.copyfile(spy_path, LIBGRAPH_PATH)
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)

            result = run_solver()
            assert result.returncode == 0, f"solver.py failed with the graph API test library: {result.stderr}"
            with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
                assert f.read().strip() == str(marker_result), "solver.py did not log the C traversal return value"

            with open(call_log, "r", encoding="utf-8") as f:
                calls = [line.strip() for line in f if line.strip()]
            expected_calls = [f"init {node_count} -1"]
            expected_calls.extend(f"edge {source} {destination}" for source, destination in edges)
            expected_calls.append("traverse 0 -1")
            assert calls == expected_calls, f"Unexpected graph API calls: {calls!r}"
        finally:
            with open(GRAPH_DEF_PATH, "wb") as f:
                f.write(original_graph)
            with open(LIBGRAPH_PATH, "wb") as f:
                f.write(original_lib)
            if original_output is None:
                if os.path.exists(OUTPUT_PATH):
                    os.remove(OUTPUT_PATH)
            else:
                with open(OUTPUT_PATH, "wb") as f:
                    f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
