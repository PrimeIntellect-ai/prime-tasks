#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

DB_PATH = "/home/user/backups.db"
C_FILE_PATH = "/home/user/recovery.c"
BINARY_PATH = "/home/user/recovery"
OUTPUT_PATH = "/home/user/recovery_path.txt"


def test_database_optimization():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_edges_bad';")
    assert cursor.fetchone() is None, "The inefficient index 'idx_edges_bad' was not dropped."

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_edges_cov';")
    assert cursor.fetchone() is not None, "The covering index 'idx_edges_cov' was not created."

    cursor.execute("PRAGMA index_info('idx_edges_cov');")
    columns = [row[2] for row in cursor.fetchall()]
    expected_columns = ['source', 'target', 'weight']
    assert columns == expected_columns, f"The index 'idx_edges_cov' does not have the correct columns or order. Expected {expected_columns}, got {columns}."

    conn.close()


def process_neighbors_body(content):
    start = content.find("void process_neighbors")
    assert start != -1, "The process_neighbors function is missing."
    opening = content.find("{", start)
    assert opening != -1, "The process_neighbors function has no body."
    depth = 0
    for pos in range(opening, len(content)):
        if content[pos] == "{":
            depth += 1
        elif content[pos] == "}":
            depth -= 1
            if depth == 0:
                return content[opening + 1:pos]
    raise AssertionError("The process_neighbors function body is incomplete.")


def derive_shortest_path(db_path, start, end):
    conn = sqlite3.connect(db_path)
    edges = conn.execute("SELECT source, target, weight FROM edges").fetchall()
    conn.close()

    graph = {}
    for source, target, weight in edges:
        graph.setdefault(source, []).append((target, weight))

    distances = {start: 0}
    previous = {}
    queue = [(0, start)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        if node == end:
            break
        for target, weight in graph.get(node, []):
            candidate = distance + weight
            if candidate < distances.get(target, float("inf")):
                distances[target] = candidate
                previous[target] = node
                heapq.heappush(queue, (candidate, target))

    assert end in distances, "Verifier test graph unexpectedly has no path."
    path = []
    current = end
    while True:
        path.append(current)
        if current == start:
            break
        current = previous[current]
    return "->".join(reversed(path)) + "\n"


def test_c_code_implemented_and_executable():
    assert os.path.isfile(C_FILE_PATH), f"C source file {C_FILE_PATH} is missing."

    with open(C_FILE_PATH, "r") as f:
        content = f.read()

    assert "sqlite3_prepare" in content, "The C file does not use 'sqlite3_prepare' or 'sqlite3_prepare_v2'."
    assert "sqlite3_bind_text" in content, "The C file does not use 'sqlite3_bind_text' for parameterized queries."
    assert "sprintf" not in process_neighbors_body(content), "The C file should not use sprintf inside the query building logic."

    assert os.path.isfile(BINARY_PATH), f"Compiled program {BINARY_PATH} is missing."
    assert os.access(BINARY_PATH, os.X_OK), f"Compiled program {BINARY_PATH} is not executable."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY_PATH} is not a compiled ELF executable."

    submitted = subprocess.run(
        [BINARY_PATH, "Start", "Recovery"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert submitted.returncode == 0, f"Compiled program failed: {submitted.stderr}"
    assert submitted.stdout == "Start->B->A->C->Recovery\n", f"Compiled program produced incorrect output: {submitted.stdout!r}"

    with tempfile.TemporaryDirectory() as temp_dir:
        test_binary = os.path.join(temp_dir, "recovery")
        compile_result = subprocess.run(
            ["gcc", C_FILE_PATH, "-lsqlite3", "-o", test_binary],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, f"recovery.c does not compile: {compile_result.stderr}"

        test_db = os.path.join(temp_dir, "backups.db")
        source_conn = sqlite3.connect(DB_PATH)
        destination_conn = sqlite3.connect(test_db)
        source_conn.backup(destination_conn)
        source_conn.close()

        suffix = uuid.uuid4().hex[:10]
        start = "S" + suffix
        middle = "M" + suffix
        decoy = "D" + suffix
        end = "E" + suffix
        destination_conn.executemany("INSERT INTO nodes(id) VALUES (?)", [(start,), (middle,), (decoy,), (end,)])
        destination_conn.executemany(
            "INSERT INTO edges(source, target, weight) VALUES (?, ?, ?)",
            [(start, decoy, 20), (start, middle, 2), (middle, end, 3), (decoy, end, 1)],
        )
        destination_conn.commit()
        destination_conn.close()

        expected = derive_shortest_path(test_db, start, end)
        result = subprocess.run(
            [test_binary, start, end],
            cwd=temp_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, f"Program failed on verifier graph: {result.stderr}"
        assert result.stdout == expected, f"Program did not compute the derived shortest path. Expected {expected!r}, got {result.stdout!r}."


def test_recovery_path_output():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."

    with open(OUTPUT_PATH, "r") as f:
        content = f.read().strip()

    expected_path = "Start->B->A->C->Recovery"
    assert content == expected_path, f"The calculated recovery path is incorrect. Expected '{expected_path}', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
