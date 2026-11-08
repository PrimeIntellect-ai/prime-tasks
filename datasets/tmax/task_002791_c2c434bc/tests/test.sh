#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
from collections import deque

SOURCE = "/home/user/find_path.c"
EXECUTABLE = "/home/user/find_path"
RESULT = "/home/user/path_result.txt"
LINEAGE = "/home/user/etl_lineage.tsv"
EXPECTED_ORIGINAL = "raw_users,dim_fast_track,mart_revenue"


def test_find_path_c_exists():
    """Test that the C source file exists."""
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} is missing."
    with open(SOURCE, "r") as f:
        content = f.read()
    assert len(content.strip()) > 0, f"C source file {SOURCE} is empty."


def test_find_path_executable_exists():
    """Test that the compiled executable exists and is executable."""
    assert os.path.isfile(EXECUTABLE), f"Executable file {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "find_path is not a compiled ELF executable."


def test_path_result_content():
    """Test that the path_result.txt file contains the correct shortest path."""
    assert os.path.isfile(RESULT), f"Result file {RESULT} is missing."
    with open(RESULT, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_ORIGINAL, \
        f"Expected path '{EXPECTED_ORIGINAL}', but got '{content}'."


def shortest_distance(edges):
    graph = {}
    for source, target in edges:
        graph.setdefault(source, []).append(target)
    queue = deque([("raw_users", 0)])
    seen = {"raw_users"}
    while queue:
        node, distance = queue.popleft()
        if node == "mart_revenue":
            return distance
        for target in graph.get(node, []):
            if target not in seen:
                seen.add(target)
                queue.append((target, distance + 1))
    raise AssertionError("Verifier generated a graph without a path")


def check_result(edges):
    assert os.path.isfile(RESULT), "Program did not create /home/user/path_result.txt"
    with open(RESULT, "r") as f:
        raw = f.read()
    lines = raw.splitlines()
    assert len(lines) == 1, "Result must contain exactly one line"
    path = lines[0].split(",")
    assert path[0] == "raw_users", "Path does not start at raw_users"
    assert path[-1] == "mart_revenue", "Path does not end at mart_revenue"
    edge_set = set(edges)
    assert all((path[i], path[i + 1]) in edge_set for i in range(len(path) - 1)), \
        f"Result contains an edge not present in the supplied TSV: {lines[0]}"
    assert len(path) - 1 == shortest_distance(edges), \
        f"Result is not a shortest path for the supplied TSV: {lines[0]}"
    return lines[0]


def run_case(binary, edges):
    shuffled = list(edges)
    random.SystemRandom().shuffle(shuffled)
    data = "".join(f"{source}\t{target}\n" for source, target in shuffled)
    if os.path.exists(RESULT):
        os.remove(RESULT)
    completed = subprocess.run(
        [binary], input=data, text=True, cwd="/home/user",
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert completed.returncode == 0, \
        f"{binary} exited with status {completed.returncode}: {completed.stderr}"
    return check_result(shuffled)


def test_program_processes_stdin_and_finds_shortest_paths():
    compiled = "/tmp/find_path_from_source"
    build = subprocess.run(
        ["gcc", "-std=c11", SOURCE, "-o", compiled],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert build.returncode == 0, f"find_path.c does not compile with gcc: {build.stderr}"

    with open(LINEAGE, "r") as f:
        original_edges = [tuple(line.rstrip("\n").split("\t")) for line in f if line.strip()]

    token = secrets.token_hex(4)
    a, b, c = [f"node_{token}_{x}" for x in "abc"]
    d, e, f, g = [f"long_{token}_{x}" for x in "defg"]
    hidden_edges = [
        ("raw_users", a), (a, b), (b, c), (c, "mart_revenue"),
        ("raw_users", d), (d, e), (e, f), (f, g), (g, "mart_revenue"),
        (a, d), (b, e)
    ]
    direct_edges = [
        ("raw_users", f"decoy_{token}"),
        (f"decoy_{token}", "mart_revenue"),
        ("raw_users", "mart_revenue"),
        (f"unused_{token}", f"unused2_{token}")
    ]

    for binary in (EXECUTABLE, compiled):
        original_result = run_case(binary, original_edges)
        assert original_result == EXPECTED_ORIGINAL, \
            f"Expected path '{EXPECTED_ORIGINAL}', but got '{original_result}'."
        run_case(binary, hidden_edges)
        run_case(binary, direct_edges)

    # Restore and revalidate the requested result using the submitted executable.
    restored = run_case(EXECUTABLE, original_edges)
    assert restored == EXPECTED_ORIGINAL, \
        f"Expected path '{EXPECTED_ORIGINAL}', but got '{restored}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
