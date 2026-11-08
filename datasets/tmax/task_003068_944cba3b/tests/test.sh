#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import os
import random
import re
import secrets
import sqlite3
import subprocess
import pytest


def test_scripts_exist_and_executable():
    """Verify that the three bash scripts exist and are executable."""
    scripts = [
        "/home/user/init_db.sh",
        "/home/user/find_shortest_path.sh",
        "/home/user/pipeline.sh"
    ]
    for script in scripts:
        assert os.path.isfile(script), f"Script {script} does not exist."
        assert os.access(script, os.X_OK), f"Script {script} is not executable."


def test_database_exists_and_populated():
    """Verify that the SQLite database exists and has the correct table and data."""
    db_path = "/home/user/network.db"
    assert os.path.isfile(db_path), f"Database {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='edges';")
    table_exists = cursor.fetchone()
    assert table_exists is not None, "Table 'edges' does not exist in the database."

    cursor.execute("SELECT COUNT(*) FROM edges;")
    count = cursor.fetchone()[0]
    assert count > 0, "Table 'edges' is empty."

    conn.close()


def test_optimized_routes_log():
    """Verify that the optimized routes log is generated with the correct contents."""
    log_path = "/home/user/optimized_routes.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "DC1,DC4,23,DC1-DC2-DC3-DC4",
        "DC1,DC5,33,DC1-DC2-DC3-DC4-DC5",
        "DC2,DC6,30,DC2-DC3-DC4-DC5-DC6",
        "DC3,DC6,23,DC3-DC4-DC5-DC6"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in log, found {len(lines)}."

    for expected in expected_lines:
        assert expected in lines, f"Expected route '{expected}' not found in {log_path}."


def run_script(path, *args):
    return subprocess.run(
        [path, *args], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=15, check=True
    )


def shortest_path(nodes, edges, start, end):
    adjacency = {node: [] for node in nodes}
    for source, target, latency in edges:
        adjacency[source].append((target, latency))

    queue = [(0, (start,), start)]
    best = {start: 0}
    while queue:
        total, path, node = heapq.heappop(queue)
        if total != best.get(node):
            continue
        if node == end:
            return total, list(path)
        for target, latency in adjacency[node]:
            candidate = total + latency
            if candidate < best.get(target, float("inf")):
                best[target] = candidate
                heapq.heappush(queue, (candidate, path + (target,), target))
    raise AssertionError(f"No path from {start} to {end} in verifier graph")


def assert_finder_result(start, end, expected):
    completed = run_script("/home/user/find_shortest_path.sh", start, end)
    output = completed.stdout.strip()
    expected_output = f"{expected[0]}|{'-'.join(expected[1])}"
    assert output == expected_output, (
        f"find_shortest_path.sh returned {output!r} for {start}->{end}; "
        f"expected {expected_output!r}. stderr={completed.stderr!r}"
    )


def test_scripts_execute_etl_and_solve_runtime_graph():
    with open("/home/user/find_shortest_path.sh", "r", errors="replace") as handle:
        finder_source = handle.read()
    active_source = "\n".join(
        line for line in finder_source.splitlines()
        if not line.lstrip().startswith("#")
    )
    assert re.search(r"\bWITH\s+RECURSIVE\b", active_source, re.IGNORECASE), (
        "find_shortest_path.sh must construct a WITH RECURSIVE SQLite query"
    )

    rng = random.SystemRandom()
    token = secrets.token_hex(4)
    nodes = [f"N{token}{i}" for i in range(7)]

    chain_weights = [rng.randint(3, 14) for _ in range(6)]
    edges = [(nodes[i], nodes[i + 1], chain_weights[i]) for i in range(6)]
    for i in range(5):
        chain_cost = chain_weights[i] + chain_weights[i + 1]
        edges.append((nodes[i], nodes[i + 2], chain_cost + rng.randint(7, 25)))
    edges.extend([
        (nodes[0], nodes[4], sum(chain_weights[0:4]) + rng.randint(15, 35)),
        (nodes[1], nodes[6], sum(chain_weights[1:6]) + rng.randint(15, 35)),
        (nodes[0], nodes[6], sum(chain_weights) + rng.randint(25, 50)),
    ])
    rng.shuffle(edges)

    with open("/home/user/network_edges.csv", "w", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["source", "target", "latency"])
        writer.writerows(edges)

    if os.path.exists("/home/user/network.db"):
        os.remove("/home/user/network.db")
    run_script("/home/user/init_db.sh")

    assert os.path.isfile("/home/user/network.db"), "init_db.sh did not create network.db"
    with sqlite3.connect("/home/user/network.db") as conn:
        schema = conn.execute("PRAGMA table_info(edges)").fetchall()
        columns = [(row[1], row[2].upper()) for row in schema]
        assert columns == [("source", "TEXT"), ("target", "TEXT"), ("latency", "INTEGER")]
        loaded = conn.execute("SELECT source, target, latency FROM edges").fetchall()
    assert sorted(loaded) == sorted(edges), "init_db.sh did not import the runtime CSV exactly"

    route_pairs = [
        (nodes[0], nodes[3]),
        (nodes[1], nodes[6]),
        (nodes[2], nodes[5]),
        (nodes[0], nodes[6]),
    ]
    expected = {
        pair: shortest_path(nodes, edges, pair[0], pair[1])
        for pair in route_pairs
    }
    for start, end in route_pairs:
        assert_finder_result(start, end, expected[(start, end)])

    with open("/home/user/routes_to_calc.csv", "w", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerows(route_pairs)

    marker = f"/tmp/pipeline_calls_{token}"
    real_init = f"/tmp/submitted_init_{token}.sh"
    real_finder = f"/tmp/submitted_finder_{token}.sh"
    os.rename("/home/user/init_db.sh", real_init)
    os.rename("/home/user/find_shortest_path.sh", real_finder)
    try:
        with open("/home/user/init_db.sh", "w") as handle:
            handle.write(f"#!/bin/bash\necho init >> {marker}\nexec {real_init} \"$@\"\n")
        with open("/home/user/find_shortest_path.sh", "w") as handle:
            handle.write(
                f"#!/bin/bash\necho \"find|$1|$2\" >> {marker}\n"
                f"exec {real_finder} \"$@\"\n"
            )
        os.chmod("/home/user/init_db.sh", 0o755)
        os.chmod("/home/user/find_shortest_path.sh", 0o755)

        for path in ["/home/user/network.db", "/home/user/optimized_routes.log", marker]:
            if os.path.exists(path):
                os.remove(path)
        run_script("/home/user/pipeline.sh")

        assert os.path.isfile(marker), "pipeline.sh did not invoke the modular scripts"
        with open(marker) as handle:
            calls = [line.strip() for line in handle if line.strip()]
        assert calls.count("init") == 1, "pipeline.sh must invoke init_db.sh first and once"
        expected_calls = [f"find|{start}|{end}" for start, end in route_pairs]
        assert calls == ["init", *expected_calls], (
            "pipeline.sh must call find_shortest_path.sh once for each route, in file order"
        )

        assert os.path.isfile("/home/user/optimized_routes.log"), "pipeline.sh did not create the log"
        with open("/home/user/optimized_routes.log") as handle:
            actual_lines = [line.rstrip("\n") for line in handle]
        expected_lines = [
            f"{start},{end},{expected[(start, end)][0]},{'-'.join(expected[(start, end)][1])}"
            for start, end in route_pairs
        ]
        assert actual_lines == expected_lines, "pipeline.sh produced an incorrect runtime route log"
    finally:
        for submitted, original in [
            (real_init, "/home/user/init_db.sh"),
            (real_finder, "/home/user/find_shortest_path.sh"),
        ]:
            if os.path.exists(submitted):
                if os.path.exists(original):
                    os.remove(original)
                os.rename(submitted, original)
        if os.path.exists(marker):
            os.remove(marker)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
