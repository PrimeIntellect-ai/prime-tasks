#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile

SOURCE = "/home/user/process_graph.c"
DATABASE = "/home/user/dataset.db"
CSV_PATH = "/home/user/heavy_triangles.csv"
EXECUTABLE = "/tmp/process_graph_verifier"


def read_csv(path):
    with open(path, "r", newline="") as f:
        return [[cell.strip() for cell in row] for row in csv.reader(f) if row]


def build_program():
    result = subprocess.run(
        ["gcc", "-Wall", "-Wextra", "-o", EXECUTABLE, SOURCE, "-lsqlite3"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"C program did not compile:\n{result.stderr}"


def run_program():
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(
        ["sudo", "-u", "user", "--", EXECUTABLE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(CSV_PATH), f"File {CSV_PATH} does not exist. Did you run your C program?"


def test_c_program_exists():
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} does not exist."
    source = open(SOURCE, "r", encoding="utf-8", errors="replace").read()
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", source), "Program must include sqlite3.h."
    assert re.search(r"\bsqlite3_open(?:_v2)?\s*\(", source), "Program must open the database using the SQLite C API."
    assert re.search(r"\bNOT\s+INDEXED\b", source, re.IGNORECASE), "The edges query must use NOT INDEXED."
    build_program()


def test_heavy_triangles_csv():
    build_program()
    run_program()

    expected_rows = [
        ["node_id", "label", "out_degree"],
        ["1", "Alpha", "2"],
        ["2", "Bravo", "3"],
        ["3", "Charlie", "1"]
    ]

    actual_rows = read_csv(CSV_PATH)
    assert actual_rows == expected_rows, f"CSV contents do not match expected.\nExpected: {expected_rows}\nActual: {actual_rows}"


def test_program_on_independent_graph():
    build_program()
    rng = random.SystemRandom()
    ids = rng.sample(range(100, 10000), 8)
    a, b, c, d, e, f, g, h = ids
    nodes = [(node_id, f"Node{rng.randrange(100000, 999999)}") for node_id in ids]

    edges = [
        (a, b, rng.randint(35, 45)),
        (b, c, rng.randint(35, 45)),
        (c, a, rng.randint(35, 45)),
        (c, d, rng.randint(40, 50)),
        (d, e, rng.randint(30, 40)),
        (e, c, rng.randint(35, 45)),
        (f, g, 8),
        (g, h, 9),
        (h, f, 10),
        (a, d, 7),
        (b, e, 11),
        (b, f, 13),
        (d, a, 5),
        (e, h, 6),
    ]

    labels = dict(nodes)
    edge_weights = {(s, t): w for s, t, w in edges}
    heavy_nodes = set()
    for x in ids:
        for y in ids:
            for z in ids:
                if len({x, y, z}) != 3:
                    continue
                if (x, y) in edge_weights and (y, z) in edge_weights and (z, x) in edge_weights:
                    if edge_weights[(x, y)] + edge_weights[(y, z)] + edge_weights[(z, x)] > 100:
                        heavy_nodes.update((x, y, z))

    out_degrees = {node_id: sum(1 for s, _, _ in edges if s == node_id) for node_id in ids}
    expected = [["node_id", "label", "out_degree"]]
    expected.extend(
        [[str(node_id), labels[node_id], str(out_degrees[node_id])] for node_id in sorted(heavy_nodes)]
    )

    backup_dir = tempfile.mkdtemp(prefix="graph-verifier-")
    database_backup = os.path.join(backup_dir, "dataset.db")
    csv_backup = os.path.join(backup_dir, "heavy_triangles.csv")
    shutil.copy2(DATABASE, database_backup)
    had_csv = os.path.isfile(CSV_PATH)
    if had_csv:
        shutil.copy2(CSV_PATH, csv_backup)

    try:
        for suffix in ("", "-wal", "-shm"):
            path = DATABASE + suffix
            if os.path.exists(path):
                os.remove(path)

        connection = sqlite3.connect(DATABASE)
        connection.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY, label TEXT)")
        connection.execute("CREATE TABLE edges (source INTEGER, target INTEGER, weight INTEGER)")
        connection.executemany("INSERT INTO nodes(id, label) VALUES (?, ?)", nodes)
        connection.executemany("INSERT INTO edges(source, target, weight) VALUES (?, ?, ?)", edges)
        connection.execute("CREATE INDEX idx_edges_source_target ON edges(source, target)")
        connection.commit()
        connection.close()
        os.chmod(DATABASE, 0o666)

        run_program()
        actual = read_csv(CSV_PATH)
        assert actual == expected, f"Program failed on an independent graph.\nExpected: {expected}\nActual: {actual}"
    finally:
        for suffix in ("", "-wal", "-shm"):
            path = DATABASE + suffix
            if os.path.exists(path):
                os.remove(path)
        shutil.copy2(database_backup, DATABASE)
        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)
        if had_csv:
            shutil.copy2(csv_backup, CSV_PATH)
        shutil.rmtree(backup_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
