#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import subprocess
import uuid

DB_PATH = "/home/user/graph.db"
SOURCE_PATH = "/home/user/extract_deps.c"
EXE_PATH = "/home/user/extract_deps"
CSV_PATH = "/home/user/etl_output.csv"


def read_output():
    assert os.path.exists(CSV_PATH), "Output file /home/user/etl_output.csv is missing."
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def run_program(executable, package_name):
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(
        [executable, package_name],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{executable} failed for package {package_name!r}: {result.stderr}"
    )
    return read_output()


def expected_from_database(package_name):
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            "SELECT id FROM packages WHERE name = ?", (package_name,)
        ).fetchall()
        assert len(rows) == 1, f"Test package {package_name!r} is not unique."
        root_id = rows[0][0]

        names = dict(conn.execute("SELECT id, name FROM packages"))
        edges = {}
        for pkg_id, dependency_id in conn.execute(
            "SELECT pkg_id, depends_on_id FROM dependencies"
        ):
            edges.setdefault(pkg_id, []).append(dependency_id)

        depths = {}
        frontier = [(root_id, 0)]
        while frontier:
            node, depth = frontier.pop(0)
            for dependency_id in edges.get(node, []):
                candidate_depth = depth + 1
                if dependency_id not in depths or candidate_depth < depths[dependency_id]:
                    depths[dependency_id] = candidate_depth
                    frontier.append((dependency_id, candidate_depth))

        return [
            f"{depth},{names[node_id]}"
            for node_id, depth in sorted(
                depths.items(), key=lambda item: (item[1], names[item[0]])
            )
        ]
    finally:
        conn.close()


def test_complete_solution():
    # Preserve the original database/index assertion.
    assert os.path.exists(DB_PATH), "Database file /home/user/graph.db is missing."
    conn = sqlite3.connect(DB_PATH)
    try:
        index_count = conn.execute(
            "SELECT count(*) FROM sqlite_master WHERE type='index' AND tbl_name='dependencies'"
        ).fetchone()[0]
        assert index_count > 0, "No index created on the 'dependencies' table to speed up lookups."

        # Recursive expansion looks up outgoing edges by dependencies.pkg_id.
        useful_index = False
        for row in conn.execute("PRAGMA index_list('dependencies')"):
            index_name = row[1]
            columns = list(conn.execute(f"PRAGMA index_info('{index_name}')"))
            if columns and columns[0][2] == "pkg_id":
                useful_index = True
                break
        assert useful_index, (
            "The dependencies table needs an index whose leading column is pkg_id."
        )
    finally:
        conn.close()

    # Preserve the original executable assertions and ensure it is a compiled binary.
    assert os.path.exists(EXE_PATH), "Compiled executable /home/user/extract_deps is missing."
    assert os.access(EXE_PATH, os.X_OK), "/home/user/extract_deps is not executable."
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/extract_deps is not a compiled ELF executable."

    assert os.path.isfile(SOURCE_PATH), "/home/user/extract_deps.c is missing."
    source = open(SOURCE_PATH, "r", encoding="utf-8").read()
    source_without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    assert re.search(r"\bWITH\s+RECURSIVE\b", source_without_comments, re.I), (
        "The C source does not contain a recursive CTE."
    )
    assert re.search(r"\bsqlite3_bind_text\s*\(", source_without_comments), (
        "The C source does not call sqlite3_bind_text."
    )

    # Execute the submitted artifact and preserve the original exact lib_alpha check.
    expected_alpha = [
        "1,lib_beta",
        "1,lib_gamma",
        "2,lib_delta",
        "3,lib_epsilon",
        "4,lib_zeta",
    ]
    alpha_lines = run_program(EXE_PATH, "lib_alpha")
    assert alpha_lines == expected_alpha, (
        f"etl_output.csv content does not match exactly. Expected {expected_alpha}, but got {alpha_lines}."
    )

    # Add an unpredictable graph and package name, including a quote, to exercise
    # parameter binding, recursion, duplicate convergence, and result ordering.
    token = uuid.uuid4().hex
    dynamic_names = [
        f"root_{token}'quoted",
        f"branch_b_{token}",
        f"branch_a_{token}",
        f"shared_{token}",
        f"leaf_{token}",
        f"unrelated_{token}",
    ]
    conn = sqlite3.connect(DB_PATH)
    try:
        next_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM packages").fetchone()[0]
        ids = list(range(next_id, next_id + len(dynamic_names)))
        conn.executemany(
            "INSERT INTO packages(id, name) VALUES (?, ?)", zip(ids, dynamic_names)
        )
        root, branch_b, branch_a, shared, leaf, unrelated = ids
        conn.executemany(
            "INSERT INTO dependencies(pkg_id, depends_on_id) VALUES (?, ?)",
            [
                (root, branch_b),
                (root, branch_a),
                (branch_b, shared),
                (branch_a, shared),
                (shared, leaf),
                (unrelated, leaf),
            ],
        )
        conn.commit()
    finally:
        conn.close()

    dynamic_root = dynamic_names[0]
    expected_dynamic = expected_from_database(dynamic_root)
    assert run_program(EXE_PATH, dynamic_root) == expected_dynamic, (
        "The submitted executable did not correctly traverse a parameterized package graph."
    )

    # Compile the submitted C source independently and exercise that build too.
    rebuilt = "/tmp/extract_deps_from_source"
    compile_result = subprocess.run(
        ["gcc", "-o", rebuilt, SOURCE_PATH, "-lsqlite3"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"The C source does not compile: {compile_result.stderr}"
    assert run_program(rebuilt, dynamic_root) == expected_dynamic, (
        "A fresh build of extract_deps.c does not produce the correct recursive result."
    )

    # Leave the requested final lib_alpha output in place.
    final_alpha = run_program(EXE_PATH, "lib_alpha")
    assert final_alpha == expected_alpha
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
