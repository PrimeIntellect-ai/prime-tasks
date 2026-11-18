#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import string
import subprocess
from collections import deque

SOURCE = "/home/user/graph_tool.c"
EXECUTABLE = "/home/user/graph_tool"
COMPILED = "/tmp/verified_graph_tool"
INPUT = "/home/user/citation_graph.csv"
OUTPUT = "/home/user/page2.csv"


def compile_source():
    if not os.path.exists(COMPILED):
        proc = subprocess.run(
            ["gcc", SOURCE, "-o", COMPILED],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert proc.returncode == 0, f"graph_tool.c did not compile:\n{proc.stderr}"
    return COMPILED


def run_tool(path):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    proc = subprocess.run(
        [path],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert proc.returncode == 0, (
        f"{path} exited with {proc.returncode}.\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    assert os.path.exists(OUTPUT), f"{path} did not create {OUTPUT}"
    assert os.path.isfile(OUTPUT), f"The path {OUTPUT} is not a file."
    with open(OUTPUT, "r", newline="") as f:
        return [line.strip() for line in f.read().splitlines() if line.strip()]


def expected_lines(records):
    latest_active = {}
    for edge_id, child, parent, timestamp, is_active in records:
        if is_active != 1:
            continue
        key = (child, parent)
        if key not in latest_active or timestamp > latest_active[key]:
            latest_active[key] = timestamp

    adjacency = {}
    for child, parent in latest_active:
        adjacency.setdefault(parent, set()).add(child)

    depths = {"ROOT": 0}
    queue = deque(["ROOT"])
    while queue:
        parent = queue.popleft()
        for child in adjacency.get(parent, ()):
            candidate = depths[parent] + 1
            if child not in depths or candidate < depths[child]:
                depths[child] = candidate
                queue.append(child)

    descendants = sorted(
        ((node, depth) for node, depth in depths.items() if node != "ROOT"),
        key=lambda item: (item[1], item[0]),
    )
    return ["node,depth"] + [f"{node},{depth}" for node, depth in descendants[10:20]]


def write_records(records):
    with open(INPUT, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["edge_id", "child", "parent", "timestamp", "is_active"])
        writer.writerows(records)


def test_source_code_exists():
    assert os.path.exists(SOURCE), f"The source code file {SOURCE} is missing."
    assert os.path.isfile(SOURCE), f"The path {SOURCE} is not a file."
    compile_source()


def test_executable_exists():
    assert os.path.exists(EXECUTABLE), f"The executable file {EXECUTABLE} is missing."
    assert os.path.isfile(EXECUTABLE), f"The path {EXECUTABLE} is not a file."
    assert os.access(EXECUTABLE, os.X_OK), f"The file {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF executable."


def test_page2_csv_contents():
    expected_content = """node,depth
K,2
L,2
M,3
N,3
O,3
P,3
Q,3
R,3
S,3
T,3"""
    expected = [line.strip() for line in expected_content.splitlines() if line.strip()]

    for tool in (EXECUTABLE, compile_source()):
        actual_lines = run_tool(tool)
        assert actual_lines == expected, (
            f"The contents of {OUTPUT} produced by {tool} do not match the expected output.\n"
            f"Expected:\n{expected_content}\n\nActual:\n" + "\n".join(actual_lines)
        )


def test_behavior_on_generated_graph():
    alphabet = string.ascii_uppercase
    token = "".join(secrets.choice(alphabet) for _ in range(8))
    counter = 0

    def node():
        nonlocal counter
        counter += 1
        return f"N{token}{counter:02d}"

    level1 = [node() for _ in range(7)]
    level2 = [node() for _ in range(14)]
    level3 = [node() for _ in range(12)]
    inactive = node()
    disconnected1 = node()
    disconnected2 = node()

    raw = []
    timestamp = 100

    def add(child, parent, active=1, ts=None):
        nonlocal timestamp
        timestamp += 7
        raw.append([0, child, parent, timestamp if ts is None else ts, active])

    for child in level1:
        add(child, "ROOT")
    for i, child in enumerate(level2):
        add(child, level1[i % len(level1)])
    for i, child in enumerate(level3):
        add(child, level2[i % len(level2)])

    # Alternate paths, a reachable cycle, active duplicates, inactive distractors,
    # and an unreachable component exercise shortest paths and filtering.
    add(level3[0], level1[5])
    add(level1[0], level2[0])
    add(level2[3], level1[3], ts=5)
    add(level2[3], level1[3], ts=9999)
    add(inactive, "ROOT", active=0)
    add(level3[4], "ROOT", active=0, ts=10000)
    add(disconnected1, "NOWHERE")
    add(disconnected2, disconnected1)

    secrets.SystemRandom().shuffle(raw)
    records = []
    for edge_id, row in enumerate(raw, 1):
        records.append([edge_id, row[1], row[2], row[3], row[4]])

    write_records(records)
    expected = expected_lines(records)
    for tool in (EXECUTABLE, compile_source()):
        actual = run_tool(tool)
        assert actual == expected, (
            f"Incorrect filtering, traversal, sorting, or pagination from {tool}.\n"
            f"Expected: {expected}\nActual: {actual}"
        )


def test_invalid_schema_exits_two_and_prints_error():
    with open(INPUT, "w", newline="") as f:
        f.write("edge_id,parent,child,timestamp,is_active\n")
        f.write("1,ROOT,A,1,1\n")

    for tool in (EXECUTABLE, compile_source()):
        proc = subprocess.run(
            [tool],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert proc.returncode == 2, f"{tool} returned {proc.returncode} for an invalid header, not 2."
        assert proc.stdout.strip() or proc.stderr.strip(), f"{tool} did not print an error for an invalid header."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
