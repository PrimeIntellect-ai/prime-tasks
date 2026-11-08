#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import pytest

PIPELINE = "/home/user/pipeline.py"
SOURCE = "/home/user/graph_solver.c"
SOLVER = "/home/user/graph_solver"
OUTPUT = "/home/user/execution_order.txt"


def run_command(command, *, input_text=None, env=None):
    return subprocess.run(
        command,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        env=env,
    )


def parse_and_validate(stdout, nodes, edges, description):
    lines = stdout.splitlines()
    assert lines, f"{description} produced no output. stderr: {stdout!r}"
    assert all(line and len(line) == 1 and 'A' <= line <= 'Z' for line in lines), (
        f"{description} must output only one uppercase node per line, but produced {lines!r}."
    )
    assert len(lines) == len(nodes), (
        f"{description} output {len(lines)} nodes, expected {len(nodes)}: {lines!r}"
    )
    assert len(set(lines)) == len(lines), f"{description} output duplicate nodes: {lines!r}"
    assert set(lines) == set(nodes), (
        f"{description} output the wrong node set. Expected {sorted(nodes)!r}, got {lines!r}."
    )
    positions = {node: index for index, node in enumerate(lines)}
    for source, target in edges:
        assert positions[source] < positions[target], (
            f"{description} violates dependency {source} -> {target}: {lines!r}"
        )
    return lines


def make_random_graph():
    rng = secrets.SystemRandom()
    count = rng.randint(7, 18)
    nodes = list("ABCDEFGHIJKLMNOPQRSTUVWXYZ"[:count])
    rng.shuffle(nodes)

    # A chain ensures every selected node is represented in the input while the
    # shuffled order prevents a fixed alphabetical answer from passing.
    edges = [(nodes[i], nodes[i + 1]) for i in range(count - 1)]
    existing = set(edges)
    for i in range(count):
        for j in range(i + 2, count):
            edge = (nodes[i], nodes[j])
            if edge not in existing and rng.random() < 0.22:
                edges.append(edge)
                existing.add(edge)
    rng.shuffle(edges)
    graph = "".join(f"{u} -> {v}\n" for u, v in edges)
    return nodes, edges, graph


def test_execution_order_output():
    assert os.path.isfile(OUTPUT), (
        f"Output file {OUTPUT} does not exist. Did you run the pipeline and redirect the output?"
    )

    with open(OUTPUT, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    valid_sort_1 = ['A', 'B', 'C', 'D', 'E']
    valid_sort_2 = ['A', 'C', 'B', 'D', 'E']

    assert lines == valid_sort_1 or lines == valid_sort_2, (
        f"The execution order in {OUTPUT} is incorrect. "
        f"Expected {valid_sort_1} or {valid_sort_2}, but got {lines}."
    )

    result = run_command(["python3", PIPELINE, "/home/user/graph.txt"])
    assert result.returncode == 0, (
        f"The pipeline failed on graph.txt with status {result.returncode}: {result.stderr}"
    )
    assert result.stdout.splitlines() == lines, (
        f"{OUTPUT} does not match the output currently produced by the pipeline. "
        f"Pipeline output: {result.stdout.splitlines()!r}; file: {lines!r}"
    )


def test_pipeline_py_is_valid_python3():
    assert os.path.isfile(PIPELINE), f"File {PIPELINE} is missing."

    with open(PIPELINE, 'r') as f:
        code = f.read()

    try:
        compile(code, PIPELINE, 'exec')
    except SyntaxError as e:
        pytest.fail(
            f"{PIPELINE} contains a Python 3 SyntaxError: {e}. Ensure all Python 2 "
            "syntax (like print statements) is fixed."
        )


def test_graph_solver_c_fixed():
    assert os.path.isfile(SOURCE), f"File {SOURCE} is missing."

    with open(SOURCE, 'r') as f:
        code = f.read()

    buggy_line = "int sorted_nodes[26];"
    assert buggy_line not in code, (
        f"{SOURCE} still contains the buggy local array allocation: '{buggy_line}'. "
        "You must allocate this array dynamically (e.g., malloc) or make it static."
    )


def test_graph_solver_compiled():
    assert os.path.isfile(SOLVER), (
        f"Compiled executable {SOLVER} does not exist. Did you run build.sh?"
    )
    assert os.access(SOLVER, os.X_OK), f"File {SOLVER} is not executable."


def test_compiled_solver_and_pipeline_on_unseen_graphs():
    for iteration in range(3):
        nodes, edges, graph = make_random_graph()

        backend = run_command([SOLVER], input_text=graph)
        assert backend.returncode == 0, (
            f"Compiled backend failed on generated graph {iteration}: {backend.stderr}"
        )
        parse_and_validate(backend.stdout, nodes, edges, "compiled backend")

        with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as graph_file:
            graph_file.write(graph)
            graph_path = graph_file.name
        try:
            pipeline = run_command(["python3", PIPELINE, graph_path])
        finally:
            os.unlink(graph_path)

        assert pipeline.returncode == 0, (
            f"Pipeline failed on generated graph {iteration}: {pipeline.stderr}"
        )
        parse_and_validate(pipeline.stdout, nodes, edges, "Python pipeline")


def test_source_is_memory_safe_and_functional():
    sanitized_solver = "/tmp/graph_solver_sanitized"
    compile_result = run_command([
        "gcc", "-O1", "-g", "-Wall", "-Wextra",
        "-fsanitize=address,undefined", "-fno-sanitize-recover=all",
        SOURCE, "-o", sanitized_solver,
    ])
    assert compile_result.returncode == 0, (
        f"The fixed C source does not compile with memory-safety instrumentation: "
        f"{compile_result.stderr}"
    )

    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
    env["UBSAN_OPTIONS"] = "halt_on_error=1"

    # All 26 nodes require room for 26 results plus the -1 terminator.
    nodes = list("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    edges = [(nodes[i], nodes[i + 1]) for i in range(25)]
    graph = "".join(f"{u} -> {v}\n" for u, v in edges)
    result = run_command([sanitized_solver], input_text=graph, env=env)
    assert result.returncode == 0, (
        "The C source failed under AddressSanitizer/UndefinedBehaviorSanitizer. "
        f"This indicates the returned result array is still unsafe. stderr: {result.stderr}"
    )
    parse_and_validate(result.stdout, nodes, edges, "sanitized C backend")

    nodes, edges, graph = make_random_graph()
    result = run_command([sanitized_solver], input_text=graph, env=env)
    assert result.returncode == 0, (
        f"Sanitized C backend failed on a generated graph: {result.stderr}"
    )
    parse_and_validate(result.stdout, nodes, edges, "sanitized C backend")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
