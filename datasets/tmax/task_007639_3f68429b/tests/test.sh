#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
from pathlib import Path

SOURCE = "/home/user/extract_subgraph.c"
EXECUTABLE = "/home/user/extract_subgraph"
DATABASE = "/home/user/network.db"
CSV_PATH = "/home/user/out_degrees.csv"
COMPILED_COPY = "/tmp/extract_subgraph_from_source"


def test_source_file_exists():
    """Check if the C source file exists."""
    assert os.path.exists(SOURCE), "The C source file /home/user/extract_subgraph.c does not exist."


def test_executable_exists():
    """Check if the compiled executable exists and is a native executable."""
    assert os.path.exists(EXECUTABLE), "The executable /home/user/extract_subgraph does not exist."
    assert os.access(EXECUTABLE, os.X_OK), "The file /home/user/extract_subgraph is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The submitted executable is not a compiled ELF program."


def test_source_uses_required_sqlite_features():
    code = Path(SOURCE).read_text(errors="replace")
    lower = code.lower()
    assert re.search(r"\bsqlite3_open(?:_v2)?\s*\(", lower), "Source must open the SQLite database."
    assert re.search(r"\bsqlite3_prepare(?:_v[23])?\s*\(", lower), "Source must prepare an SQL statement."
    assert re.search(r"\bsqlite3_bind_[a-z0-9_]+\s*\(", lower), "Source must bind the start_node parameter."
    assert re.search(r"\bwith\b", lower) and re.search(r"\brecursive\b", lower), \
        "The SQL must use a recursive CTE."


def run_program(program, argument):
    try:
        result = subprocess.run(
            [program, str(argument)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=5
        )
    except subprocess.TimeoutExpired:
        raise AssertionError(f"{program} timed out for start_node {argument}")
    assert result.returncode == 0, (
        f"{program} failed for start_node {argument}: {result.stderr}"
    )


def normalized_csv_lines():
    assert os.path.exists(CSV_PATH), f"The output CSV file {CSV_PATH} does not exist."
    with open(CSV_PATH, "r") as f:
        actual_content = f.read()
    return [line.strip() for line in actual_content.strip().split("\n")], actual_content


def test_argument_handling():
    for args in ([], ["1", "2"], ["not_an_integer"]):
        try:
            result = subprocess.run(
                [EXECUTABLE] + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=5
            )
        except subprocess.TimeoutExpired:
            raise AssertionError(f"Executable timed out for invalid arguments: {args}")
        assert result.returncode != 0, f"Executable accepted invalid arguments: {args}"


def test_csv_output():
    """Execute the submitted artifact and retain the original exact output assertion."""
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    run_program(EXECUTABLE, 1)

    expected_content = """node,out_degree
1,3
3,2
7,2
2,1
4,1
5,1
6,1
8,1
9,0
10,0
11,0
"""

    actual_lines, actual_content = normalized_csv_lines()
    expected_lines = [line.strip() for line in expected_content.strip().split("\n")]
    assert actual_lines == expected_lines, f"CSV content does not match expected output.\nExpected:\n{expected_content}\nActual:\n{actual_content}"


def expected_lines(start_node, edges):
    adjacency = {}
    degrees = {}
    for source, target in edges:
        adjacency.setdefault(source, []).append(target)
        degrees[source] = degrees.get(source, 0) + 1

    reachable = {start_node}
    pending = [start_node]
    while pending:
        node = pending.pop()
        for target in adjacency.get(node, []):
            if target not in reachable:
                reachable.add(target)
                pending.append(target)

    rows = sorted(((node, degrees.get(node, 0)) for node in reachable),
                  key=lambda row: (-row[1], row[0]))
    return ["node,out_degree"] + [f"{node},{degree}" for node, degree in rows]


def install_database(edges):
    for suffix in ("", "-wal", "-shm", "-journal"):
        try:
            os.remove(DATABASE + suffix)
        except FileNotFoundError:
            pass
    connection = sqlite3.connect(DATABASE)
    try:
        connection.execute("CREATE TABLE connections(source INT, target INT)")
        connection.executemany("INSERT INTO connections(source, target) VALUES (?, ?)", edges)
        connection.commit()
    finally:
        connection.close()


def verify_case(program, start_node, edges):
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    run_program(program, start_node)
    actual, content = normalized_csv_lines()
    expected = expected_lines(start_node, edges)
    assert actual == expected, (
        f"Wrong CSV from {program} for start_node {start_node}.\n"
        f"Expected: {expected}\nActual:\n{content}"
    )


def test_recompiled_source_and_dynamic_databases():
    compile_result = subprocess.run(
        ["gcc", SOURCE, "-o", COMPILED_COPY, "-lsqlite3"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compile_result.returncode == 0, f"Source did not compile with sqlite3: {compile_result.stderr}"

    original_database = Path(DATABASE).read_bytes()
    base = 10000 + secrets.randbelow(500000)
    start = base
    edges = [
        (start, base + 1), (start, base + 1), (start, base + 2),
        (base + 1, base + 3), (base + 3, base + 1),
        (base + 3, base + 3), (base + 2, base + 4),
        (base + 50, start), (base + 60, base + 61)
    ]
    isolated = base + 99

    try:
        for program in (EXECUTABLE, COMPILED_COPY):
            install_database(edges)
            verify_case(program, start, edges)
            install_database(edges)
            verify_case(program, isolated, edges)
    finally:
        for suffix in ("", "-wal", "-shm", "-journal"):
            try:
                os.remove(DATABASE + suffix)
            except FileNotFoundError:
                pass
        Path(DATABASE).write_bytes(original_database)
        try:
            run_program(EXECUTABLE, 1)
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
