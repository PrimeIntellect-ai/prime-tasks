#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import heapq
import os
import random
import re
import shutil
import sqlite3
import subprocess
import tokenize

import pytest

CSV_PATH = "/home/user/shortest_path.csv"
SCRIPT_PATH = "/home/user/find_path.py"
DB_PATH = "/home/user/routing.db"


def test_script_exists():
    """Verify that the user created a valid Python script."""
    assert os.path.isfile(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} does not exist."
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    ast.parse(source, filename=SCRIPT_PATH)


def test_shortest_path_csv():
    """Retain the original check of the submitted result."""
    assert os.path.isfile(CSV_PATH), f"Expected output file {CSV_PATH} does not exist."

    with open(CSV_PATH, "r") as f:
        content = f.read().strip().splitlines()

    expected_content = [
        "node,cumulative_latency",
        "START,0",
        "N1,2",
        "N2,3",
        "END,6"
    ]

    content = [line.strip() for line in content if line.strip()]
    expected_content = [line.strip() for line in expected_content]

    assert content == expected_content, (
        f"Contents of {CSV_PATH} do not match the expected shortest path.\n"
        f"Expected: {expected_content}\n"
        f"Got: {content}"
    )


def test_script_contains_required_active_distinct_query():
    """Check that executable source includes the required DISTINCT active-row query."""
    with tokenize.open(SCRIPT_PATH) as f:
        tokens = tokenize.generate_tokens(f.readline)
        source_without_comments = " ".join(
            token.string for token in tokens
            if token.type not in (tokenize.COMMENT, tokenize.ENCODING)
        )

    normalized = re.sub(r"\s+", " ", source_without_comments)
    assert re.search(r"\bSELECT\s+DISTINCT\b", normalized, re.IGNORECASE), (
        "find_path.py must extract network links with SELECT DISTINCT"
    )
    assert re.search(
        r"\bis_active\s*=\s*(?:1|\?|:[A-Za-z_]\w*|%s)",
        normalized,
        re.IGNORECASE,
    ), "find_path.py must restrict the extracted topology to is_active = 1"


def shortest_path_from_active_rows(edges):
    graph = {}
    for source, target, latency, is_active in set(edges):
        if is_active == 1:
            graph.setdefault(source, []).append((target, latency))

    distances = {"START": 0}
    previous = {}
    queue = [(0, "START")]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        if node == "END":
            break
        for target, latency in graph.get(node, []):
            candidate = distance + latency
            if candidate < distances.get(target, float("inf")):
                distances[target] = candidate
                previous[target] = node
                heapq.heappush(queue, (candidate, target))

    assert "END" in distances
    path = []
    node = "END"
    while True:
        path.append(node)
        if node == "START":
            break
        node = previous[node]
    path.reverse()
    return [[node, str(distances[node])] for node in path]


def test_script_is_executed_and_solves_changed_database():
    """Execute the artifact against an unpredictable topology and derive its answer."""
    rng = random.SystemRandom()
    suffix = f"{rng.randrange(10**7, 10**8)}"
    a = "A_" + suffix
    b = "B_" + suffix
    c = "C_" + suffix
    x, y, z = (rng.randrange(3, 15) for _ in range(3))
    optimum = x + y + z

    edges = [
        ("START", a, x, 1),
        (a, b, y, 1),
        (b, "END", z, 1),
        ("START", c, optimum + 4, 1),
        (c, "END", optimum + 7, 1),
        ("START", "END", optimum + 20, 1),
        (a, "END", y + z + 6, 1),
        (b, a, 1, 1),
        # Inactive rows would produce a falsely shorter result if included.
        ("START", "END", 1, 0),
        ("START", c, 1, 0),
        (c, "END", 1, 0),
        # Duplicate active rows require DISTINCT extraction.
        ("START", a, x, 1),
        (a, b, y, 1),
        (b, "END", z, 1),
    ]
    expected_rows = shortest_path_from_active_rows(edges)

    backup_db = "/tmp/routing.db.verifier-backup"
    backup_csv = "/tmp/shortest_path.csv.verifier-backup"
    shutil.copy2(DB_PATH, backup_db)
    had_csv = os.path.isfile(CSV_PATH)
    if had_csv:
        shutil.copy2(CSV_PATH, backup_csv)

    try:
        for sidecar in (DB_PATH + "-wal", DB_PATH + "-shm"):
            if os.path.exists(sidecar):
                os.remove(sidecar)
        os.remove(DB_PATH)
        connection = sqlite3.connect(DB_PATH)
        try:
            connection.execute(
                "CREATE TABLE network_links "
                "(source TEXT, target TEXT, latency INTEGER, is_active INTEGER)"
            )
            connection.executemany(
                "INSERT INTO network_links VALUES (?, ?, ?, ?)", edges
            )
            connection.commit()
        finally:
            connection.close()

        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)

        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(CSV_PATH), "Executing find_path.py did not create shortest_path.csv"

        with open(CSV_PATH, newline="", encoding="utf-8") as f:
            rows = list(csv.reader(f))
        assert rows, "shortest_path.csv is empty"
        assert rows[0] == ["node", "cumulative_latency"], (
            "CSV must contain exactly the columns node and cumulative_latency"
        )
        assert all(len(row) == 2 for row in rows), "Every CSV row must have exactly two columns"
        assert rows[1:] == expected_rows, (
            f"Script did not compute the shortest directed active path. "
            f"Expected {expected_rows}, got {rows[1:]}"
        )
    finally:
        for sidecar in (DB_PATH + "-wal", DB_PATH + "-shm"):
            if os.path.exists(sidecar):
                os.remove(sidecar)
        shutil.copy2(backup_db, DB_PATH)
        if had_csv:
            shutil.copy2(backup_csv, CSV_PATH)
        elif os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
