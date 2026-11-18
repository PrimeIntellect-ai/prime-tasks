#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import sqlite3
import subprocess

import pytest

C_FILE_PATH = "/home/user/process_graph.c"
OUTPUT_FILE_PATH = "/home/user/max_degree.txt"
DB_PATH = "/home/user/graph.db"
OUTPUT_RE = re.compile(r"Node: (-?\d+), Total Weight: (-?\d+)\n?\Z")


def expected_line(edges):
    totals = {}
    for src, _dst, weight in edges:
        totals[src] = totals.get(src, 0) + weight
    max_weight = max(totals.values())
    winners = [src for src, total in totals.items() if total == max_weight]
    assert len(winners) == 1
    return f"Node: {winners[0]}, Total Weight: {max_weight}"


def run_program(executable, edges, separator):
    data = "".join(
        f"{src}{separator}{dst}{separator}{weight}\n"
        for src, dst, weight in edges
    )
    result = subprocess.run(
        [executable],
        input=data,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, (
        f"Program exited with {result.returncode}. stderr: {result.stderr}"
    )
    assert result.stdout == expected_line(edges) + "\n", (
        f"Expected exact output {expected_line(edges)!r}, got {result.stdout!r}"
    )


def make_random_edges(winner):
    rng = random.SystemRandom()
    nodes = {winner}
    while len(nodes) < 9:
        nodes.add(rng.randint(1, 100000))

    edges = []
    for src in nodes:
        if src == winner:
            continue
        for _ in range(rng.randint(1, 4)):
            edges.append((src, rng.randint(1, 100000), rng.randint(1, 30)))

    # Split the winning total across repeated, non-adjacent source records.
    edges.extend([
        (winner, rng.randint(1, 100000), 4000),
        (winner, rng.randint(1, 100000), 5000),
        (winner, rng.randint(1, 100000), 6000),
    ])
    rng.shuffle(edges)
    return edges


@pytest.fixture(scope="session")
def executable(tmp_path_factory):
    output = tmp_path_factory.mktemp("build") / "process_graph"
    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", C_FILE_PATH, "-o", str(output)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    assert result.returncode == 0, f"C program failed to compile:\n{result.stderr}"
    return str(output)


def test_c_file_exists():
    assert os.path.exists(C_FILE_PATH), f"C program file {C_FILE_PATH} does not exist."
    assert os.path.isfile(C_FILE_PATH), f"{C_FILE_PATH} is not a file."


def test_output_file_exists():
    assert os.path.exists(OUTPUT_FILE_PATH), f"Output file {OUTPUT_FILE_PATH} does not exist."
    assert os.path.isfile(OUTPUT_FILE_PATH), f"{OUTPUT_FILE_PATH} is not a file."


def test_output_content():
    expected_node = None
    expected_weight = -1
    conn = None
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        # Derive truth explicitly from a table scan, bypassing idx_src.
        cursor.execute(
            "SELECT src, SUM(weight) AS total_weight "
            "FROM edges NOT INDEXED GROUP BY src "
            "ORDER BY total_weight DESC LIMIT 1;"
        )
        row = cursor.fetchone()
        if row:
            expected_node, expected_weight = row
    except sqlite3.Error as exc:
        pytest.fail(f"SQLite error occurred while verifying truth: {exc}")
    finally:
        if conn is not None:
            conn.close()

    assert expected_node is not None, "Could not compute expected max degree from database."
    expected_output = f"Node: {expected_node}, Total Weight: {expected_weight}"

    with open(OUTPUT_FILE_PATH, "r") as output_file:
        raw_content = output_file.read()
    content = raw_content.strip()

    # Preserve the original content assertion and additionally enforce the exact format.
    assert expected_output in content, (
        f"Expected output to contain {expected_output!r}, but got {content!r}."
    )
    assert OUTPUT_RE.fullmatch(raw_content), f"Output is not exactly one valid line: {raw_content!r}"
    assert raw_content.rstrip("\n") == expected_output and raw_content.count("\n") <= 1, (
        f"Expected exactly {expected_output!r}, got {raw_content!r}"
    )


def test_program_on_actual_table_scan(executable):
    conn = sqlite3.connect(DB_PATH)
    try:
        edges = conn.execute(
            "SELECT src, dst, weight FROM edges NOT INDEXED"
        ).fetchall()
    finally:
        conn.close()

    assert edges, "The database contains no edges."
    run_program(executable, edges, "|")


def test_program_on_unseen_pipe_input(executable):
    run_program(executable, make_random_edges(100000), "|")


def test_program_on_unseen_space_input(executable):
    winner = random.SystemRandom().randint(1, 99999)
    run_program(executable, make_random_edges(winner), " ")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
