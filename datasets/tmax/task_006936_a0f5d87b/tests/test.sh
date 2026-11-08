#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import os
import random
import shutil
import sqlite3
import subprocess

JSON_PATH = "/home/user/shortest_path.json"
CPP_PATH = "/home/user/optimizer.cpp"
DB_PATH = "/home/user/etl_graph.db"
BINARY_PATH = "/tmp/optimizer_verifier"
BACKUP_PATH = "/tmp/etl_graph.db.verifier_backup"


def run_program():
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    subprocess.run([BINARY_PATH], cwd="/home/user", check=True, timeout=20)
    assert os.path.exists(JSON_PATH), f"Output JSON file missing at {JSON_PATH}"
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is not a file"
    with open(JSON_PATH, "r") as f:
        return f.read()


def assert_output(content, expected_path, expected_latency):
    expected_str = json.dumps(
        {"path": expected_path, "total_latency": expected_latency},
        separators=(",", ":"),
    )
    assert content.strip() == expected_str, (
        f"JSON content mismatch.\nExpected exact string: {expected_str}\n"
        f"Found: {content}"
    )
    try:
        data = json.loads(content)
    except json.JSONDecodeError as exc:
        raise AssertionError("Output file does not contain valid JSON.") from exc
    assert data.get("path") == expected_path, "Incorrect path in JSON."
    assert data.get("total_latency") == expected_latency, "Incorrect total_latency in JSON."


def expected_from_database():
    conn = sqlite3.connect(DB_PATH)
    try:
        names = dict(conn.execute("SELECT id, name FROM nodes"))
        start = next(node_id for node_id, name in names.items() if name == "Extract")
        goal = next(node_id for node_id, name in names.items() if name == "Load")
        rows = conn.execute(
            """
            SELECT e.source, e.target, e.latency
            FROM edges e
            WHERE e.created_at = (
                SELECT MAX(e2.created_at)
                FROM edges e2
                WHERE e2.source = e.source AND e2.target = e.target
            )
            """
        ).fetchall()
    finally:
        conn.close()

    graph = {}
    for source, target, latency in rows:
        graph.setdefault(source, []).append((target, latency))

    distances = {start: 0}
    paths = {start: [start]}
    queue = [(0, start)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances[node]:
            continue
        if node == goal:
            break
        for target, latency in graph.get(node, []):
            candidate = distance + latency
            if candidate < distances.get(target, float("inf")):
                distances[target] = candidate
                paths[target] = paths[node] + [target]
                heapq.heappush(queue, (candidate, target))

    assert goal in distances, "Verifier-generated graph has no Extract-to-Load path"
    return [names[node] for node in paths[goal]], distances[goal]


def install_random_graph():
    rng = random.SystemRandom()
    while True:
        weights = [rng.randint(20, 200) for _ in range(9)]
        totals = [
            weights[0] + weights[1],
            weights[2] + weights[3],
            weights[4] + weights[5],
            weights[6] + weights[7],
            weights[8],
        ]
        if len(set(totals)) == len(totals):
            break

    pairs = [
        (1, 2, weights[0]), (2, 5, weights[1]),
        (1, 3, weights[2]), (3, 5, weights[3]),
        (1, 4, weights[4]), (4, 5, weights[5]),
        (2, 3, weights[6]), (3, 4, weights[7]),
        (1, 5, weights[8]),
    ]

    rows = []
    for index, (source, target, latest_latency) in enumerate(pairs):
        latest_time = 5000 + index
        # Insert the newest row first and a tempting stale row afterward so
        # insertion order cannot substitute for comparing created_at.
        rows.append((source, target, latest_latency, latest_time))
        rows.append((source, target, 1, latest_time - 1000))

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("DELETE FROM edges")
        conn.executemany(
            "INSERT INTO edges(source, target, latency, created_at) VALUES (?, ?, ?, ?)",
            rows,
        )
        conn.commit()
    finally:
        conn.close()


def test_complete_optimizer():
    assert os.path.exists(CPP_PATH), f"C++ source file missing at {CPP_PATH}"
    assert os.path.isfile(CPP_PATH), f"{CPP_PATH} is not a file"

    subprocess.run(
        ["g++", "-std=c++17", CPP_PATH, "-o", BINARY_PATH, "-lsqlite3"],
        check=True,
        timeout=30,
    )

    shutil.copy2(DB_PATH, BACKUP_PATH)
    original_content = None
    try:
        original_content = run_program()
        assert_output(
            original_content,
            ["Extract", "Clean", "Aggregate", "Load"],
            30,
        )

        for _ in range(2):
            install_random_graph()
            expected_path, expected_latency = expected_from_database()
            content = run_program()
            assert_output(content, expected_path, expected_latency)
    finally:
        shutil.copy2(BACKUP_PATH, DB_PATH)
        if original_content is not None:
            with open(JSON_PATH, "w") as f:
                f.write(original_content)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
