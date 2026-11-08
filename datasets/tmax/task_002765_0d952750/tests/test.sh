#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import stat
import subprocess
import tempfile
from collections import deque

import pytest


def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/etl/pipeline.sh"
    assert os.path.isfile(script_path), f"Bash script {script_path} does not exist."

    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Bash script {script_path} is not executable."


def test_cpp_source_exists():
    cpp_path = "/home/user/etl/graph_solver.cpp"
    assert os.path.isfile(cpp_path), f"C++ source code {cpp_path} does not exist."


def test_pipeline_execution_and_output():
    # Remove output file and executable if they exist to ensure the script creates them
    output_path = "/home/user/output/shortest_path.txt"
    executable_path = "/home/user/etl/graph_solver"

    if os.path.exists(output_path):
        os.remove(output_path)
    if os.path.exists(executable_path):
        os.remove(executable_path)

    # Run the pipeline script
    script_path = "/home/user/etl/pipeline.sh"
    try:
        result = subprocess.run(
            [script_path],
            cwd="/home/user/etl",
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Pipeline script failed with return code {result.returncode}.\n"
            f"Stderr: {result.stderr}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Pipeline script execution timed out.")

    # Check if executable was created
    assert os.path.isfile(executable_path), (
        f"Executable {executable_path} was not created by the pipeline script."
    )
    with open(executable_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", (
            f"Executable {executable_path} is not a compiled native executable."
        )

    # Check if output file was created
    assert os.path.isfile(output_path), f"Output file {output_path} was not created."

    # Check output file contents
    with open(output_path, "r") as f:
        actual_content = f.read().strip()

    expected_content = (
        "Length: 4\n"
        "Path: API_Gateway -> Data_Ingestor -> Message_Queue -> Processing_Node -> Storage_Cluster_9"
    )

    assert actual_content == expected_content, (
        f"Output file content does not match expected.\n"
        f"Expected:\n{expected_content}\n\n"
        f"Actual:\n{actual_content}"
    )


def derive_expected(tsv_path, start, end):
    graph = {}
    with open(tsv_path, newline="") as f:
        reader = csv.reader(f, delimiter="\t")
        next(reader)
        for row in reader:
            if len(row) == 3 and row[1] == "depends_on":
                graph.setdefault(row[0], []).append(row[2])

    queue = deque([start])
    parent = {start: None}
    while queue:
        node = queue.popleft()
        if node == end:
            path = []
            while node is not None:
                path.append(node)
                node = parent[node]
            path.reverse()
            return f"Length: {len(path) - 1}\nPath: {' -> '.join(path)}"
        for neighbor in graph.get(node, []):
            if neighbor not in parent:
                parent[neighbor] = node
                queue.append(neighbor)
    return "No path found."


def run_solver_on(rows, start, end):
    executable_path = "/home/user/etl/graph_solver"
    output_path = "/home/user/output/shortest_path.txt"

    with tempfile.TemporaryDirectory() as tmpdir:
        dataset_path = os.path.join(tmpdir, "alternate_graph.tsv")
        with open(dataset_path, "w", newline="") as f:
            writer = csv.writer(f, delimiter="\t", lineterminator="\n")
            writer.writerow(["Source_Node", "Relationship_Type", "Target_Node"])
            writer.writerows(rows)

        expected = derive_expected(dataset_path, start, end)
        if os.path.exists(output_path):
            os.remove(output_path)

        try:
            result = subprocess.run(
                [executable_path, dataset_path, start, end],
                cwd="/home/user/etl",
                capture_output=True,
                text=True,
                timeout=10,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("Compiled graph solver timed out on an alternate dataset.")

        assert result.returncode == 0, (
            f"Compiled graph solver failed on alternate input with return code "
            f"{result.returncode}.\nStderr: {result.stderr}"
        )
        assert os.path.isfile(output_path), "Graph solver did not create the output file."
        with open(output_path) as f:
            actual = f.read().strip()
        assert actual == expected, (
            f"Incorrect result for alternate input.\nExpected:\n{expected}\n\nActual:\n{actual}"
        )


def test_compiled_solver_on_alternate_graphs():
    # Unique shortest route; tempting direct edges use non-matching relationship types.
    run_solver_on(
        [
            ["Alpha", "related_to", "Goal"],
            ["Alpha", "depends_on ", "Goal"],
            ["Alpha", "depends_on", "Beta"],
            ["Beta", "part_of", "Goal"],
            ["Beta", "depends_on", "Gamma"],
            ["Gamma", "depends_on", "Goal"],
            ["Alpha", "depends_on", "Detour"],
            ["Detour", "depends_on", "Dead_End"],
            ["Goal", "depends_on", "Alpha"],
        ],
        "Alpha",
        "Goal",
    )

    # Directedness and relationship filtering make the requested route unreachable.
    run_solver_on(
        [
            ["West", "depends_on", "Center"],
            ["Center", "related_to", "East"],
            ["East", "depends_on", "West"],
            ["Outside", "depends_on", "West"],
        ],
        "West",
        "Outside",
    )

    # A node is its own zero-edge shortest path.
    run_solver_on(
        [["One", "depends_on", "Two"]],
        "Isolated_Node",
        "Isolated_Node",
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
