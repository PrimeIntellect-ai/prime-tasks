#!/bin/bash
set -e
mkdir -p /logs/verifier
export PATH="/opt/rust/bin:${PATH}"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import sqlite3
import subprocess
from collections import deque

DB_PATH = "/home/user/citations.db"
PATH_RESULT_FILE = "/home/user/path_result.txt"
CONCURRENCY_RESULT_FILE = "/home/user/concurrency_result.txt"
RUST_MAIN_FILE = "/home/user/dataset_manager/src/main.rs"
PROJECT_DIR = "/home/user/dataset_manager"
BINARY = "/home/user/dataset_manager/target/debug/dataset_manager"


def test_path_result():
    assert os.path.isfile(PATH_RESULT_FILE), f"Expected result file {PATH_RESULT_FILE} does not exist."
    with open(PATH_RESULT_FILE, "r") as f:
        content = f.read().strip()

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        WITH RECURSIVE path(id, depth) AS (
            SELECT 10, 0
            UNION ALL
            SELECT c.target_id, p.depth + 1
            FROM citations c
            JOIN path p ON c.source_id = p.id
            WHERE p.id != 42
        )
        SELECT min(depth) FROM path WHERE id = 42;
    """)
    row = cursor.fetchone()
    conn.close()

    expected_depth = str(row[0]) if row and row[0] is not None else "-1"
    assert content == expected_depth, (
        f"Expected path length {expected_depth}, but got {content} in {PATH_RESULT_FILE}."
    )


def test_concurrency_result():
    assert os.path.isfile(CONCURRENCY_RESULT_FILE), (
        f"Expected result file {CONCURRENCY_RESULT_FILE} does not exist."
    )
    with open(CONCURRENCY_RESULT_FILE, "r") as f:
        content = f.read().strip()
    assert "Concurrency test passed" in content, (
        f"Expected 'Concurrency test passed' in {CONCURRENCY_RESULT_FILE}, got: {content}"
    )


def test_sqlite_journal_mode():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA journal_mode;")
    mode = cursor.fetchone()[0].lower()
    conn.close()
    assert mode == "wal", f"Expected SQLite journal mode to be 'wal', but it is '{mode}'."


def test_sqlite_index_exists():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA index_list('citations');")
    indexes = cursor.fetchall()

    found_idx = False
    for idx in indexes:
        idx_name = idx[1]
        cursor.execute(f"PRAGMA index_info('{idx_name}');")
        columns = [col[2] for col in cursor.fetchall()]
        if columns == ['source_id', 'target_id'] or columns == ['target_id', 'source_id']:
            found_idx = True
            break

    conn.close()
    assert found_idx, (
        "Expected an index on the 'citations' table for columns (source_id, target_id)."
    )


def test_rust_code_modified():
    assert os.path.isfile(RUST_MAIN_FILE), f"Rust source file {RUST_MAIN_FILE} missing."
    with open(RUST_MAIN_FILE, "r") as f:
        content = f.read()

    assert "WITH RECURSIVE" in content.upper(), (
        "Did not find 'WITH RECURSIVE' CTE in the Rust source code."
    )
    assert (
        "PRAGMA journal_mode" in content
        or "journal_mode=WAL" in content.upper()
        or "journal_mode = WAL" in content.upper()
    ), "Did not find journal_mode configuration in the Rust source code."


def build_program():
    result = subprocess.run(
        ["cargo", "build", "--quiet"],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, f"Rust project failed to build:\n{result.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), (
        "Compiled dataset_manager executable was not produced."
    )


def run_program(args, timeout=20):
    result = subprocess.run(
        [BINARY] + args,
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"Program invocation {args!r} failed with code {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return result.stdout.strip()


def bfs_distance(edges, source, target):
    if source == target:
        return 0
    adjacency = {}
    for left, right in edges:
        adjacency.setdefault(left, []).append(right)
    queue = deque([(source, 0)])
    seen = {source}
    while queue:
        node, depth = queue.popleft()
        for nxt in adjacency.get(node, []):
            if nxt == target:
                return depth + 1
            if nxt not in seen:
                seen.add(nxt)
                queue.append((nxt, depth + 1))
    return -1


def test_execute_concurrency_and_randomized_paths():
    build_program()

    # Reset the persistent mode before execution. The submitted connection setup
    # must switch it back to WAL when the concurrency command actually runs.
    conn = sqlite3.connect(DB_PATH, timeout=10)
    mode = conn.execute("PRAGMA journal_mode=DELETE;").fetchone()[0].lower()
    conn.close()
    assert mode == "delete", f"Could not reset journal mode before runtime test: {mode}"

    concurrency_output = run_program(["test-concurrency"])
    assert "Concurrency test passed" in concurrency_output, (
        f"Executed concurrency command did not report success: {concurrency_output!r}"
    )

    conn = sqlite3.connect(DB_PATH)
    runtime_mode = conn.execute("PRAGMA journal_mode;").fetchone()[0].lower()
    conn.close()
    assert runtime_mode == "wal", (
        "Running the submitted program did not configure the database connection for WAL mode."
    )

    # Install a verifier-generated graph with unpredictable IDs, then exercise
    # the compiled shortest-path implementation on several independently
    # derived answers rather than trusting the fixed result file.
    ids = []
    while len(ids) < 20:
        candidate = 100000 + secrets.randbelow(900000)
        if candidate not in ids:
            ids.append(candidate)

    edges = {
        (ids[0], ids[1]),
        (ids[1], ids[2]),
        (ids[2], ids[3]),
        (ids[4], ids[5]),
        (ids[6], ids[7]),
        (ids[7], ids[8]),
    }
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            if secrets.randbelow(100) < 17:
                edges.add((ids[i], ids[j]))

    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.execute("DELETE FROM citations")
    conn.execute("DELETE FROM papers")
    conn.executemany(
        "INSERT INTO papers(id, title) VALUES (?, ?)",
        [(paper_id, f"paper-{paper_id}") for paper_id in ids],
    )
    conn.executemany(
        "INSERT INTO citations(source_id, target_id) VALUES (?, ?)",
        list(edges),
    )
    conn.commit()
    conn.close()

    cases = [
        (ids[0], ids[3]),
        (ids[4], ids[5]),
        (ids[-1], ids[0]),
        (ids[9], ids[9]),
    ]
    for _ in range(6):
        cases.append((ids[secrets.randbelow(len(ids))], ids[secrets.randbelow(len(ids))]))

    for source, target in cases:
        expected = bfs_distance(edges, source, target)
        output = run_program(["path", str(source), str(target)])
        assert re.fullmatch(r"-?\d+", output), (
            f"Path command for {source}->{target} did not print just an integer: {output!r}"
        )
        actual = int(output)
        assert actual == expected, (
            f"Incorrect shortest path for verifier-generated case {source}->{target}: "
            f"expected {expected}, got {actual}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
