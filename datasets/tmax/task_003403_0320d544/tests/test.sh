#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

DB = "/home/user/network.db"
OUTPUT = "/home/user/optimal_route.txt"
SUBMITTED_ROUTER = "/home/user/router"
COMPILED_ROUTER = "/tmp/router_from_source"


def run_router(executable, expected):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable} exited with status {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"{executable} did not create {OUTPUT}."

    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert content == expected, (
        f"Incorrect route from {executable}. Expected '{expected}', got '{content}'."
    )


def test_router_c_exists():
    assert os.path.isfile("/home/user/router.c"), "/home/user/router.c does not exist."


def test_router_executable_exists():
    assert os.path.isfile(SUBMITTED_ROUTER), "/home/user/router executable does not exist."
    assert os.access(SUBMITTED_ROUTER, os.X_OK), "/home/user/router is not executable."


def test_router_c_contains_required_sql_features():
    with open("/home/user/router.c", "r") as f:
        content = f.read().upper()

    assert "WITH RECURSIVE" in content, "The C code does not seem to use a 'WITH RECURSIVE' CTE."
    assert "OVER" in content and ("PARTITION BY" in content or "ROW_NUMBER" in content or "MAX" in content), \
        "The C code does not seem to use window functions to filter stale records."
    assert "CORE_1" in content, "The C code does not contain the starting node 'CORE_1'."
    assert "EDGE_7" in content, "The C code does not contain the ending node 'EDGE_7'."


def test_optimal_route_output():
    backup = tempfile.mktemp(prefix="network-baseline-", suffix=".db")
    shutil.copy2(DB, backup)
    try:
        run_router(SUBMITTED_ROUTER, "CORE_1->DIST_2->EDGE_7,20")
    finally:
        shutil.copy2(backup, DB)
        os.remove(backup)


def latest_edge_shortest_path(rows):
    latest = {}
    for _, src, dst, cost, updated_at in rows:
        key = (src, dst)
        if key not in latest or updated_at > latest[key][1]:
            latest[key] = (cost, updated_at)

    graph = {}
    for (src, dst), (cost, _) in latest.items():
        graph.setdefault(src, []).append((dst, cost))

    best = None

    def visit(node, path, total):
        nonlocal best
        if node == "EDGE_7":
            candidate = (total, list(path))
            if best is None or candidate[0] < best[0]:
                best = candidate
            return
        for dst, cost in graph.get(node, []):
            if dst not in path:
                visit(dst, path + [dst], total + cost)

    visit("CORE_1", ["CORE_1"], 0)
    assert best is not None
    return "->".join(best[1]) + "," + str(best[0])


def make_random_graph():
    suffix = secrets.token_hex(6).upper()
    a = "NODE_A_" + suffix
    b = "NODE_B_" + suffix
    c = "NODE_C_" + suffix
    d = "NODE_D_" + suffix

    values = [
        ("CORE_1", a, 1, 10),
        ("CORE_1", a, secrets.randbelow(11) + 80, 20),
        (a, "EDGE_7", secrets.randbelow(4) + 2, 20),
        ("CORE_1", b, secrets.randbelow(9) + 12, 20),
        (b, "EDGE_7", secrets.randbelow(9) + 12, 20),
        ("CORE_1", c, secrets.randbelow(5) + 3, 20),
        (c, d, secrets.randbelow(5) + 3, 20),
        (d, "EDGE_7", 1, 11),
        (d, "EDGE_7", secrets.randbelow(11) + 70, 21),
        ("CORE_1", "EDGE_7", secrets.randbelow(16) + 45, 20),
        (a, "CORE_1", secrets.randbelow(5) + 1, 20),
        (b, "CORE_1", secrets.randbelow(5) + 1, 20),
        (d, c, secrets.randbelow(5) + 1, 20),
    ]
    return [(i + 1, *value) for i, value in enumerate(values)]


def install_rows(rows):
    conn = sqlite3.connect(DB)
    try:
        conn.execute("DELETE FROM edges")
        conn.executemany(
            "INSERT INTO edges(id, src, dst, cost, updated_at) VALUES (?, ?, ?, ?, ?)",
            rows,
        )
        conn.commit()
    finally:
        conn.close()


def test_router_actually_queries_database_and_computes_route():
    compile_result = subprocess.run(
        ["gcc", "/home/user/router.c", "-o", COMPILED_ROUTER, "-lsqlite3"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        "router.c could not be compiled with sqlite3: " + compile_result.stderr
    )

    backup = tempfile.mktemp(prefix="network-random-", suffix=".db")
    shutil.copy2(DB, backup)
    try:
        for _ in range(3):
            rows = make_random_graph()
            expected = latest_edge_shortest_path(rows)
            install_rows(rows)

            # Exercise both the executable supplied by the agent and a fresh build
            # of the submitted C source against unpredictable database contents.
            run_router(SUBMITTED_ROUTER, expected)
            run_router(COMPILED_ROUTER, expected)
    finally:
        shutil.copy2(backup, DB)
        os.remove(backup)
        if os.path.exists(COMPILED_ROUTER):
            os.remove(COMPILED_ROUTER)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
