#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import pytest

EXE_PATH = "/home/user/backup_planner"
SOURCE_PATH = "/home/user/backup_planner.c"
GRAPH_PATH = "/home/user/db_graph.txt"
PLAN_PATH = "/home/user/backup_plan.txt"


def run_planner(exe_path, start, timeout=2):
    try:
        return subprocess.run(
            [exe_path, start], capture_output=True, text=True, timeout=timeout
        )
    except subprocess.TimeoutExpired:
        pytest.fail(
            "Execution of backup_planner timed out. It likely still contains "
            "an infinite loop or combinatorial explosion."
        )


def output_lines(result):
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def reachable(edges, start):
    adjacency = {}
    for dependent, dependency in edges:
        adjacency.setdefault(dependent, []).append(dependency)
    seen = set()
    stack = [start]
    while stack:
        node = stack.pop()
        if node in seen:
            continue
        seen.add(node)
        stack.extend(adjacency.get(node, []))
    return seen


def test_backup_planner_executable():
    assert os.path.isfile(EXE_PATH), f"Executable {EXE_PATH} does not exist."
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "backup_planner must be a compiled executable."


def test_backup_plan_output():
    assert os.path.isfile(PLAN_PATH), f"File {PLAN_PATH} does not exist."

    with open(PLAN_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = [
        "DB_AUTH",
        "DB_INVENTORY",
        "DB_LOGS",
        "DB_PRODUCTS",
        "DB_USERS",
        "DB_WEB",
    ]

    assert lines == expected, (
        f"Output in {PLAN_PATH} does not match the expected sorted unique list "
        f"of databases. Expected: {expected}, Got: {lines}"
    )


def test_executable_behavior():
    assert os.path.isfile(EXE_PATH), f"Executable {EXE_PATH} does not exist."
    result = run_planner(EXE_PATH, "DB_WEB")
    assert result.returncode == 0, (
        f"backup_planner exited with non-zero status: {result.returncode}"
    )

    lines = output_lines(result)
    assert len(lines) == len(set(lines)), (
        "Output contains duplicate entries, tracking visited nodes is likely "
        "missing or incorrect."
    )

    expected_set = {
        "DB_AUTH",
        "DB_INVENTORY",
        "DB_LOGS",
        "DB_PRODUCTS",
        "DB_USERS",
        "DB_WEB",
    }
    assert set(lines) == expected_set, (
        f"Executable output set {set(lines)} does not match expected {expected_set}."
    )


def test_source_compiles_and_handles_dynamic_graphs():
    assert os.path.isfile(SOURCE_PATH), f"Source file {SOURCE_PATH} does not exist."
    rebuilt = "/tmp/backup_planner_rebuilt"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", SOURCE_PATH, "-o", rebuilt],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert compile_result.returncode == 0, (
        "The submitted C source does not compile:\n"
        + compile_result.stdout
        + compile_result.stderr
    )
    with open(rebuilt, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Rebuilt source did not produce an ELF executable."

    token = secrets.token_hex(8)
    names = {letter: f"N_{token}_{letter}" for letter in "ABCDEFGHIJ"}
    edges = [
        (names["A"], names["B"]),
        (names["A"], names["C"]),
        (names["B"], names["D"]),
        (names["C"], names["D"]),
        (names["C"], names["F"]),
        (names["D"], names["E"]),
        (names["E"], names["B"]),
        (names["G"], names["H"]),
        (names["I"], names["J"]),
        (names["J"], names["I"]),
    ]
    starts = [names["A"], names["C"], names["G"], names["H"], names["I"]]

    with open(GRAPH_PATH, "rb") as f:
        original_graph = f.read()

    try:
        with open(GRAPH_PATH, "w") as f:
            for dependent, dependency in edges:
                f.write(f"{dependent} {dependency}\n")

        for executable in (EXE_PATH, rebuilt):
            for start in starts:
                result = run_planner(executable, start)
                assert result.returncode == 0, (
                    f"{executable} exited with status {result.returncode} for {start}."
                )
                lines = output_lines(result)
                assert len(lines) == len(set(lines)), (
                    f"{executable} printed duplicate nodes for start {start}: {lines}"
                )
                expected = reachable(edges, start)
                assert set(lines) == expected, (
                    f"{executable} returned the wrong reachable set for {start}. "
                    f"Expected {expected}, got {set(lines)}."
                )
    finally:
        with open(GRAPH_PATH, "wb") as f:
            f.write(original_graph)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
