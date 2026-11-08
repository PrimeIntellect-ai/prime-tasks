#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import sqlite3
import subprocess

C_PATH = "/home/user/query.c"
DB_PATH = "/home/user/dataset.db"
RESULT_PATH = "/home/user/result.txt"
EXE_PATH = "/tmp/query_submission"


def create_database(nodes, edges):
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    con = sqlite3.connect(DB_PATH)
    try:
        con.executescript("""
            CREATE TABLE concept_nodes (
                id INTEGER PRIMARY KEY,
                label TEXT
            );
            CREATE TABLE concept_edges (
                source_id INTEGER,
                target_id INTEGER,
                FOREIGN KEY(source_id) REFERENCES concept_nodes(id),
                FOREIGN KEY(target_id) REFERENCES concept_nodes(id)
            );
        """)
        con.executemany(
            "INSERT INTO concept_nodes(id, label) VALUES (?, ?)",
            [(node_id, f"Concept {node_id}") for node_id in nodes],
        )
        con.executemany(
            "INSERT INTO concept_edges(source_id, target_id) VALUES (?, ?)",
            edges,
        )
        con.commit()
    finally:
        con.close()


def create_canonical_database():
    create_database(
        list(range(1, 11)),
        [
            (1, 2), (3, 2), (4, 2), (5, 2),
            (6, 1), (7, 3), (8, 4), (9, 5), (10, 6),
        ],
    )


def expected_from_database():
    con = sqlite3.connect(DB_PATH)
    try:
        row = con.execute("""
            SELECT n.id
            FROM concept_nodes AS n
            LEFT JOIN concept_edges AS e ON e.target_id = n.id
            GROUP BY n.id
            ORDER BY COUNT(e.source_id) DESC, n.id ASC
            LIMIT 1
        """).fetchone()
        assert row is not None
        target = row[0]
        sources = [r[0] for r in con.execute("""
            SELECT DISTINCT e1.source_id
            FROM concept_edges AS e1
            JOIN concept_edges AS e2 ON e1.target_id = e2.source_id
            WHERE e2.target_id = ?
            ORDER BY e1.source_id ASC
        """, (target,))]
        return [str(target)] + [str(value) for value in sources]
    finally:
        con.close()


def run_submission():
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)
    completed = subprocess.run(
        [EXE_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"Compiled C program exited with status {completed.returncode}.\n"
        f"stdout: {completed.stdout}\nstderr: {completed.stderr}"
    )
    assert os.path.isfile(RESULT_PATH), (
        f"File {RESULT_PATH} does not exist after running the compiled C program."
    )
    with open(RESULT_PATH, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def test_query_c_exists():
    assert os.path.isfile(C_PATH), f"C source file {C_PATH} does not exist."


def test_compiled_program_queries_database_and_writes_results():
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", C_PATH, "-o", EXE_PATH, "-lsqlite3"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"{C_PATH} failed to compile with libsqlite3.\n"
        f"stdout: {compile_result.stdout}\nstderr: {compile_result.stderr}"
    )

    ldd_output = subprocess.check_output(["ldd", EXE_PATH], text=True)
    assert "libsqlite3" in ldd_output, "Compiled program is not linked to libsqlite3."

    nm_output = subprocess.check_output(["nm", "-D", EXE_PATH], text=True)
    assert re.search(r"sqlite3_(?:open|open_v2)(?:@|\s|$)", nm_output), (
        "Compiled program does not import a sqlite3 database-opening function."
    )
    assert re.search(r"sqlite3_(?:exec|prepare|prepare_v2|prepare_v3|get_table)(?:@|\s|$)", nm_output), (
        "Compiled program does not import a sqlite3 query-execution function."
    )

    # Preserve the original exact-content assertion, but generate the file by
    # actually executing the submitted program against the canonical dataset.
    create_canonical_database()
    canonical_lines = run_submission()
    expected_lines = ["2", "6", "7", "8", "9"]
    assert canonical_lines == expected_lines, (
        f"Content of {RESULT_PATH} is incorrect.\n"
        f"Expected lines: {expected_lines}\nActual lines: {canonical_lines}"
    )

    # Replace the database with an unpredictable, structurally equivalent case.
    # The maximum in-degree is tied, exercising the smallest-ID tie breaker.
    base = random.SystemRandom().randint(1000, 1000000) * 20
    nodes = [base + i for i in range(1, 13)]
    edges = [
        (base + 1, base + 4),
        (base + 2, base + 4),
        (base + 3, base + 4),
        (base + 8, base + 7),
        (base + 9, base + 7),
        (base + 10, base + 7),
        (base + 5, base + 1),
        (base + 6, base + 2),
        (base + 11, base + 3),
        (base + 12, base + 5),
    ]
    create_database(nodes, edges)
    dynamic_expected = expected_from_database()
    dynamic_actual = run_submission()
    assert dynamic_actual == dynamic_expected, (
        "Program output did not track the contents of a changed database.\n"
        f"Expected lines: {dynamic_expected}\nActual lines: {dynamic_actual}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
