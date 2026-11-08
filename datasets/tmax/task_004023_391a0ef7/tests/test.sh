#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
from pathlib import Path
import random
import re
import subprocess

import pytest

CPP_PATH = Path("/home/user/process_graph.cpp")
INPUT_PATH = Path("/home/user/query_plan.csv")
OUTPUT_PATH = Path("/home/user/optimized_path.txt")
EXECUTABLE = Path("/tmp/process_graph_submission")
INTEGER_RE = re.compile(r"[+-]?\d+")


@pytest.fixture(scope="session", autouse=True)
def restore_original_files():
    original_input = INPUT_PATH.read_bytes() if INPUT_PATH.exists() else None
    original_output = OUTPUT_PATH.read_bytes() if OUTPUT_PATH.exists() else None
    yield
    if original_input is not None:
        INPUT_PATH.write_bytes(original_input)
    if original_output is not None:
        OUTPUT_PATH.write_bytes(original_output)
    elif OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()
    if EXECUTABLE.exists():
        EXECUTABLE.unlink()


def test_cpp_file_exists():
    cpp_path = "/home/user/process_graph.cpp"
    assert os.path.exists(cpp_path), f"The C++ source file {cpp_path} is missing."
    assert os.path.isfile(cpp_path), f"{cpp_path} is not a file."


def test_output_file_exists_and_correct():
    out_path = "/home/user/optimized_path.txt"
    assert os.path.exists(out_path), f"The output file {out_path} is missing. Did you run your C++ program?"
    assert os.path.isfile(out_path), f"{out_path} is not a file."

    with open(out_path, "r") as f:
        content = f.read().strip()

    expected = "START->JOB_A->JOB_B->END"
    assert content == expected, f"The content of {out_path} is incorrect. Expected '{expected}', got '{content}'."


def test_source_compiles():
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", str(CPP_PATH), "-o", str(EXECUTABLE)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"process_graph.cpp did not compile:\n{result.stderr}"
    assert EXECUTABLE.is_file(), "Compilation did not produce an executable."


def parse_valid_edges(csv_text):
    edges = []
    for line in csv_text.splitlines():
        fields = line.split(",")
        if len(fields) != 3:
            continue
        parent, child, cost_text = fields
        if not parent or not child or INTEGER_RE.fullmatch(cost_text) is None:
            continue
        cost = int(cost_text)
        if cost >= 1000:
            continue
        edges.append((parent, child, cost))
    return edges


def shortest_distance(edges):
    graph = {}
    for parent, child, cost in edges:
        graph.setdefault(parent, []).append((child, cost))

    distances = {"START": 0}
    queue = [(0, "START")]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        if node == "END":
            return distance
        for child, cost in graph.get(node, []):
            candidate = distance + cost
            if candidate < distances.get(child, float("inf")):
                distances[child] = candidate
                heapq.heappush(queue, (candidate, child))
    return None


def assert_program_solves(csv_text):
    edges = parse_valid_edges(csv_text)
    optimum = shortest_distance(edges)
    assert optimum is not None, "Verifier generated an input without a START-to-END path."

    INPUT_PATH.write_text(csv_text)
    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()

    result = subprocess.run(
        [str(EXECUTABLE)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert OUTPUT_PATH.is_file(), "Program did not create /home/user/optimized_path.txt."

    content = OUTPUT_PATH.read_text().strip()
    nodes = content.split("->") if content else []
    assert len(nodes) >= 2, f"Output is not a path: {content!r}"
    assert content == "->".join(nodes), f"Output has invalid path formatting: {content!r}"
    assert nodes[0] == "START" and nodes[-1] == "END", (
        f"Path must run from START to END, got {content!r}."
    )

    pair_costs = {}
    for parent, child, cost in edges:
        key = (parent, child)
        pair_costs[key] = min(cost, pair_costs.get(key, cost))

    total = 0
    for parent, child in zip(nodes, nodes[1:]):
        assert (parent, child) in pair_costs, (
            f"Output uses an invalid, malformed, or filtered edge {parent}->{child}."
        )
        total += pair_costs[(parent, child)]
    assert total == optimum, f"Path cost {total} is not the optimal cost {optimum}."


def test_schema_filtering_and_shortest_path():
    csv_text = """ParentJob,ChildJob,ExecutionCost
START,SAFE,40
SAFE,END,7
START,CROSS,1000
CROSS,END,1
START,BADNUM,1junk
BADNUM,END,1
START,EXTRA,1,ignored
EXTRA,END,1
MALFORMED_LINE_NO_COMMAS
START,DIRECT,90
DIRECT,END,10
"""
    assert_program_solves(csv_text)


def test_program_handles_changed_graph():
    csv_text = """ParentJob,ChildJob,ExecutionCost
START,RED,70
RED,END,2
START,BLUE,10
BLUE,GREEN,10
GREEN,END,10
START,END,1001
BLUE,END,800
"""
    assert_program_solves(csv_text)


def test_program_on_derived_generated_input():
    rng = random.Random(928417)
    nodes = ["START"] + [f"N{i}" for i in range(9)] + ["END"]
    lines = ["ParentJob,ChildJob,ExecutionCost"]

    for index in range(len(nodes) - 1):
        lines.append(f"{nodes[index]},{nodes[index + 1]},{rng.randint(8, 35)}")

    for left in range(len(nodes) - 2):
        for right in range(left + 2, len(nodes)):
            if rng.random() < 0.38:
                lines.append(f"{nodes[left]},{nodes[right]},{rng.randint(25, 180)}")

    lines.extend([
        "START,FILTERED_SHORTCUT,5000",
        "FILTERED_SHORTCUT,END,1",
        "START,MALFORMED_SHORTCUT,2oops",
        "MALFORMED_SHORTCUT,END,1",
        "START,TOO,MANY,FIELDS",
        "BROKEN",
    ])
    assert_program_solves("\n".join(lines) + "\n")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
