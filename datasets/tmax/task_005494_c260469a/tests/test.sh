#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import os
import re
import secrets
import sqlite3
import subprocess
import sys
from collections import deque

CPP = "/home/user/db_traversal.cpp"
EXE = "/home/user/db_traversal"
DB = "/home/user/network.db"
LOG = "/home/user/optimized_paths.log"
REBUILT = "/tmp/db_traversal_verified"

ORIGINAL_EDGES = [
    ("Service_A", "Service_B"),
    ("Service_A", "Service_C"),
    ("Service_B", "Service_D"),
    ("Service_C", "Service_D"),
    ("Service_D", "Service_E"),
    ("Service_C", "Service_F"),
    ("Service_E", "Service_G"),
    ("Service_F", "Service_E"),
]
ORIGINAL_EXPECTED = [
    "Node: Service_B, Shortest Depth: 1",
    "Node: Service_C, Shortest Depth: 1",
    "Node: Service_D, Shortest Depth: 2",
    "Node: Service_E, Shortest Depth: 3",
    "Node: Service_F, Shortest Depth: 2",
    "Node: Service_G, Shortest Depth: 4",
]

def require(condition, message):
    if not condition:
        raise AssertionError(message)

def create_database(edges):
    if os.path.exists(DB):
        os.unlink(DB)
    connection = sqlite3.connect(DB)
    try:
        connection.execute("CREATE TABLE edges (source TEXT, target TEXT)")
        connection.executemany("INSERT INTO edges(source, target) VALUES (?, ?)", edges)
        connection.commit()
    finally:
        connection.close()

def expected_output(edges):
    adjacency = {}
    for source, target in edges:
        adjacency.setdefault(source, []).append(target)

    distances = {"Service_A": 0}
    queue = deque(["Service_A"])
    while queue:
        source = queue.popleft()
        for target in adjacency.get(source, []):
            if target not in distances:
                distances[target] = distances[source] + 1
                queue.append(target)

    return [
        f"Node: {node}, Shortest Depth: {distances[node]}"
        for node in sorted(distances)
        if node != "Service_A"
    ]

def run_and_check(executable, edges, expected, label):
    create_database(edges)
    if os.path.exists(LOG):
        os.unlink(LOG)

    try:
        result = subprocess.run(
            [executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, timeout=8, check=False
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(f"{label} timed out") from exc

    require(result.returncode == 0,
            f"{label} exited with {result.returncode}. stderr: {result.stderr}")
    require(os.path.isfile(LOG), f"{label} did not create {LOG}")
    with open(LOG, "r", encoding="utf-8") as handle:
        actual = [line.strip() for line in handle if line.strip()]
    require(actual == expected,
            f"{label} produced incorrect output.\nExpected:\n" +
            "\n".join(expected) + "\nActual:\n" + "\n".join(actual))

def sqlite_symbols(path):
    result = subprocess.run(
        ["nm", "-D", path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, check=False
    )
    require(result.returncode == 0, f"Could not inspect SQLite linkage in {path}")
    return result.stdout

def main():
    # Preserve the original source and recursive-CTE assertions.
    require(os.path.isfile(CPP), f"C++ source file {CPP} is missing.")
    with open(CPP, "r", encoding="utf-8") as handle:
        content = handle.read()
    require(re.search(r"WITH\s+RECURSIVE", content, re.IGNORECASE) is not None,
            "The C++ file does not contain a 'WITH RECURSIVE' CTE query.")

    # Preserve the original executable assertions and ensure it is a compiled binary.
    require(os.path.isfile(EXE), f"Compiled executable {EXE} is missing.")
    require(os.access(EXE, os.X_OK), f"File {EXE} is not executable.")
    with open(EXE, "rb") as handle:
        require(handle.read(4) == b"\x7fELF",
                f"{EXE} is not a compiled ELF executable.")

    # Execute the submitted artifact on the original database and retain the exact log check.
    run_and_check(EXE, ORIGINAL_EDGES, ORIGINAL_EXPECTED, "submitted executable on original graph")

    # Recompile the submitted source with the required compiler/linker options so tests exercise it.
    compile_result = subprocess.run(
        ["g++", CPP, "-lsqlite3", "-o", REBUILT],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False
    )
    require(compile_result.returncode == 0,
            "The submitted source does not compile with the required command:\n" +
            compile_result.stderr)

    # Confirm that the implementation links to and uses the scaffold's SQLite statement API.
    symbols = sqlite_symbols(REBUILT)
    for symbol in ("sqlite3_open", "sqlite3_prepare_v2", "sqlite3_step"):
        require(re.search(rf"\b{re.escape(symbol)}(?:@|$)", symbols, re.MULTILINE) is not None,
                f"Compiled source does not use required SQLite C API function {symbol}.")

    # Use unpredictable node names so a fixed six-line log cannot pass.
    token = secrets.token_hex(6)
    nodes = [f"Dynamic_{token}_{letter}" for letter in "ABCDEFGH"]
    a, b, c, d, e, f, g, h = nodes
    dynamic_edges_one = [
        ("Service_A", a), ("Service_A", b),
        (a, c), (b, c),
        (c, d), (b, e), (e, d),
        (d, f), (a, f),
        (f, g),
        (h, f),  # disconnected source must not make h reachable
    ]
    run_and_check(EXE, dynamic_edges_one, expected_output(dynamic_edges_one),
                  "submitted executable on dynamic graph")

    # Exercise the freshly compiled source on a second topology with competing paths.
    token2 = secrets.token_hex(6)
    nodes2 = [f"Probe_{token2}_{letter}" for letter in "JKLMNOPQ"]
    j, k, l, m, n, o, p, q = nodes2
    dynamic_edges_two = [
        ("Service_A", j), ("Service_A", k),
        (j, l), (l, m), (k, m),
        (m, n), (j, o), (o, n),
        (n, p),
        (q, p),  # disconnected source
    ]
    run_and_check(REBUILT, dynamic_edges_two, expected_output(dynamic_edges_two),
                  "recompiled source on dynamic graph")

if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
