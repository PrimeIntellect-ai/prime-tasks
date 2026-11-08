#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import os
import random
import secrets
import shutil
import sqlite3
import subprocess

import pytest

PLANNER_PATH = "/home/user/planner.go"
JSON_PATH = "/home/user/restore_plan.json"
DB_PATH = "/home/user/backup_meta.db"
BINARY_PATH = "/tmp/planner_under_test"


def run_command(args, timeout=30):
    return subprocess.run(
        args,
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )


def run_planner(source, target):
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    result = run_command([BINARY_PATH, source, target])
    assert result.returncode == 0, f"Planner failed for {source!r} -> {target!r}:\n{result.stdout}"
    assert os.path.isfile(JSON_PATH), "Planner did not create /home/user/restore_plan.json"
    with open(JSON_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Planner produced invalid JSON: {exc}")


@pytest.fixture(scope="session", autouse=True)
def build_and_run_initial_plan():
    assert os.path.isfile(PLANNER_PATH), f"Go program {PLANNER_PATH} is missing."
    build = run_command(["go", "build", "-o", BINARY_PATH, PLANNER_PATH], timeout=120)
    assert build.returncode == 0, f"planner.go did not compile:\n{build.stdout}"
    run_planner("Alpha", "Epsilon")


def test_planner_script_exists():
    assert os.path.isfile(PLANNER_PATH), f"Go program {PLANNER_PATH} is missing."


def test_json_output_exists():
    assert os.path.isfile(JSON_PATH), f"Output JSON file {JSON_PATH} is missing."


def test_json_output_content():
    assert os.path.isfile(JSON_PATH), f"Output JSON file {JSON_PATH} is missing."

    with open(JSON_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} is not valid JSON.")

    assert "path" in data, "Key 'path' missing in JSON output."
    assert "total_latency_ms" in data, "Key 'total_latency_ms' missing in JSON output."
    assert "total_backup_gb" in data, "Key 'total_backup_gb' missing in JSON output."

    assert data["path"] == ["Alpha", "Beta", "Delta", "Epsilon"], \
        f"Expected path ['Alpha', 'Beta', 'Delta', 'Epsilon'], but got {data['path']}"

    assert data["total_latency_ms"] == 35, \
        f"Expected total_latency_ms to be 35, but got {data['total_latency_ms']}"

    assert data["total_backup_gb"] == 1000, \
        f"Expected total_backup_gb to be 1000, but got {data['total_backup_gb']}"


def test_exact_argument_count_is_enforced():
    for args in ([], ["Alpha", "Epsilon", "extra"]):
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        result = run_command([BINARY_PATH] + args)
        assert result.returncode != 0, f"Planner accepted invalid argument list: {args!r}"
        assert not os.path.exists(JSON_PATH), "Planner generated a plan despite an invalid argument count"


def shortest_path(names, ids, edges, source_index, target_index):
    adjacency = {node_id: [] for node_id in ids}
    for source_id, target_id, latency in edges:
        adjacency[source_id].append((target_id, latency))

    source_id = ids[source_index]
    target_id = ids[target_index]
    distances = {source_id: 0}
    previous = {}
    queue = [(0, source_id)]

    while queue:
        distance, node_id = heapq.heappop(queue)
        if distance != distances.get(node_id):
            continue
        if node_id == target_id:
            break
        for neighbor, latency in adjacency[node_id]:
            candidate = distance + latency
            if candidate < distances.get(neighbor, float("inf")):
                distances[neighbor] = candidate
                previous[neighbor] = node_id
                heapq.heappush(queue, (candidate, neighbor))

    assert target_id in distances
    path_ids = []
    current = target_id
    while True:
        path_ids.append(current)
        if current == source_id:
            break
        current = previous[current]
    path_ids.reverse()
    name_by_id = dict(zip(ids, names))
    return [name_by_id[node_id] for node_id in path_ids], distances[target_id], path_ids


def test_planner_reads_database_and_computes_dynamic_directed_paths():
    original_db = "/tmp/original_backup_meta.db"
    shutil.copy2(DB_PATH, original_db)
    token = secrets.token_hex(5)
    rng = random.SystemRandom()
    ids = [11, 23, 38, 52, 71, 89, 104]
    names = [f"node_{i}_{token}'quoted" for i in range(len(ids))]

    edge_indexes = [
        (0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6),
        (0, 2), (0, 3), (1, 3), (1, 4), (2, 4), (2, 5),
        (3, 6), (4, 6),
    ]
    unique_latencies = [2 ** power for power in range(2, 2 + len(edge_indexes))]
    rng.shuffle(unique_latencies)
    edges = [
        (ids[source], ids[target], latency)
        for (source, target), latency in zip(edge_indexes, unique_latencies)
    ]
    # This very cheap edge is reverse-only. Treating links as undirected gives a wrong direct path.
    edges.append((ids[6], ids[0], 1))

    completed_by_id = {}
    try:
        os.remove(DB_PATH)
        connection = sqlite3.connect(DB_PATH)
        connection.executescript("""
            CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT UNIQUE);
            CREATE TABLE backups (id INTEGER PRIMARY KEY, node_id INTEGER, size_gb INTEGER, status TEXT);
            CREATE TABLE links (source_id INTEGER, target_id INTEGER, latency_ms INTEGER);
        """)
        for node_id, name in zip(ids, names):
            connection.execute("INSERT INTO nodes(id, name) VALUES (?, ?)", (node_id, name))
            completed_sizes = [rng.randint(17, 300), rng.randint(301, 900)]
            completed_by_id[node_id] = sum(completed_sizes)
            for size in completed_sizes:
                connection.execute(
                    "INSERT INTO backups(node_id, size_gb, status) VALUES (?, ?, 'COMPLETED')",
                    (node_id, size),
                )
            connection.execute(
                "INSERT INTO backups(node_id, size_gb, status) VALUES (?, ?, 'FAILED')",
                (node_id, rng.randint(5000, 9000)),
            )
        connection.executemany(
            "INSERT INTO links(source_id, target_id, latency_ms) VALUES (?, ?, ?)", edges
        )
        connection.commit()
        connection.close()

        for source_index, target_index in [(0, 6), (1, 5), (2, 6)]:
            expected_path, expected_latency, path_ids = shortest_path(
                names, ids, edges, source_index, target_index
            )
            expected_backup = sum(completed_by_id[node_id] for node_id in path_ids)
            data = run_planner(names[source_index], names[target_index])
            assert set(data.keys()) == {"path", "total_latency_ms", "total_backup_gb"}, \
                f"Unexpected JSON structure: {data!r}"
            assert data["path"] == expected_path
            assert data["total_latency_ms"] == expected_latency
            assert data["total_backup_gb"] == expected_backup
    finally:
        shutil.copy2(original_db, DB_PATH)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
