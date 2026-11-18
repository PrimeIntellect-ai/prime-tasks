#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import heapq
import os
import random
import secrets
import sqlite3
import stat
import subprocess

HOME = "/home/user"
DB = os.path.join(HOME, "backup_meta.db")
GET_LINKS = os.path.join(HOME, "get_links.sh")
CALC = os.path.join(HOME, "calc_shortest_path.sh")
PLAN = os.path.join(HOME, "restore_plan.txt")
TARGET = "db-target-01"


def read_plan():
    assert os.path.exists(PLAN), f"File {PLAN} does not exist."
    with open(PLAN, "r") as f:
        return f.read().strip()


def source_server():
    with sqlite3.connect(DB) as conn:
        rows = conn.execute(
            "SELECT s.hostname FROM backups b "
            "JOIN servers s ON s.id = b.server_id "
            "WHERE b.db_name = ?",
            ("main_prod",),
        ).fetchall()
    assert len(rows) == 1, "Expected exactly one server holding main_prod."
    return rows[0][0]


def expected_shortest(edges, source, target):
    graph = collections.defaultdict(list)
    for u, v, weight in edges:
        graph[u].append((v, weight))

    queue = [(0, source, [source])]
    best = {}
    while queue:
        distance, node, path = heapq.heappop(queue)
        if node in best and best[node] <= distance:
            continue
        best[node] = distance
        if node == target:
            return path, distance
        for neighbor, weight in graph[node]:
            heapq.heappush(queue, (distance + weight, neighbor, path + [neighbor]))
    raise AssertionError(f"No path from {source} to {target} in test graph")


def run_calculator(edges):
    topology = "".join(f"{u}|{v}|{w}\n" for u, v, w in edges)
    if os.path.exists(PLAN):
        os.unlink(PLAN)
    result = subprocess.run(
        [CALC],
        input=topology,
        text=True,
        capture_output=True,
        cwd=HOME,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Calculator failed with exit code {result.returncode}: {result.stderr}"
    )
    return read_plan()


def test_get_links_fixed():
    assert os.path.exists(GET_LINKS), f"Script {GET_LINKS} does not exist."
    st = os.stat(GET_LINKS)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {GET_LINKS} is not executable."

    result = subprocess.run(
        [GET_LINKS], capture_output=True, text=True, cwd=HOME, timeout=10
    )
    assert result.returncode == 0, f"Script {GET_LINKS} failed to execute."

    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert len(lines) == 6, (
        f"Expected exactly 6 rows from the fixed query, but got {len(lines)}."
    )
    for line in lines:
        parts = line.split('|')
        assert len(parts) == 3, (
            f"Output line '{line}' is not in the expected format "
            "'source|dest|latency'."
        )
        assert parts[2].isdigit(), (
            f"Latency '{parts[2]}' in line '{line}' is not a number."
        )

    with sqlite3.connect(DB) as conn:
        expected = [
            f"{source}|{dest}|{latency}"
            for source, dest, latency in conn.execute(
                "SELECT s1.hostname, s2.hostname, nl.latency "
                "FROM network_links nl "
                "JOIN servers s1 ON s1.id = nl.source_id "
                "JOIN servers s2 ON s2.id = nl.dest_id"
            )
        ]
    assert collections.Counter(lines) == collections.Counter(expected), (
        "get_links.sh output does not match the links stored in backup_meta.db."
    )


def test_calc_shortest_path_exists_and_executable():
    assert os.path.exists(CALC), f"Script {CALC} does not exist."
    st = os.stat(CALC)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {CALC} is not executable."
    with open(CALC, "r", errors="replace") as f:
        first_line = f.readline().strip().lower()
    assert first_line.startswith("#!") and "bash" in first_line, (
        "calc_shortest_path.sh must be a Bash script."
    )


def test_calculator_uses_stdin_and_computes_shortest_paths():
    src = source_server()
    rng = random.SystemRandom()

    # Runtime-generated hostnames and weights prevent a fixed plan from passing.
    # Cases alternate between a two-hop and a three-hop optimal route.
    for case in range(4):
        suffix = secrets.token_hex(6)
        a = f"relay-a-{suffix}"
        b = f"relay-b-{suffix}"
        c = f"relay-c-{suffix}"
        dead = f"dead-end-{suffix}"

        if case % 2 == 0:
            edges = [
                (src, a, rng.randint(2, 7)),
                (a, TARGET, rng.randint(2, 7)),
                (src, b, rng.randint(20, 25)),
                (b, c, rng.randint(10, 14)),
                (c, TARGET, rng.randint(10, 14)),
                (src, TARGET, rng.randint(70, 80)),
                (a, dead, rng.randint(1, 5)),
                (TARGET, src, 1),
            ]
        else:
            edges = [
                (src, a, rng.randint(20, 25)),
                (a, TARGET, rng.randint(20, 25)),
                (src, b, rng.randint(2, 4)),
                (b, c, rng.randint(2, 4)),
                (c, TARGET, rng.randint(2, 4)),
                (src, TARGET, rng.randint(70, 80)),
                (b, dead, rng.randint(1, 5)),
                (TARGET, src, 1),
            ]

        expected_path, expected_latency = expected_shortest(edges, src, TARGET)
        expected = (
            f"Path: {' -> '.join(expected_path)} | "
            f"Total Latency: {expected_latency}"
        )
        actual = run_calculator(edges)
        assert actual == expected, (
            "calc_shortest_path.sh did not compute the minimum-latency path "
            f"from its stdin. Expected '{expected}', got '{actual}'."
        )


def test_restore_plan_correct_from_database_topology():
    # Execute the required pipeline so a prewritten constant plan cannot pass.
    if os.path.exists(PLAN):
        os.unlink(PLAN)
    get_proc = subprocess.Popen(
        [GET_LINKS], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=HOME
    )
    calc_proc = subprocess.run(
        [CALC],
        stdin=get_proc.stdout,
        capture_output=True,
        text=True,
        cwd=HOME,
        timeout=10,
    )
    get_proc.stdout.close()
    get_stderr = get_proc.stderr.read()
    get_returncode = get_proc.wait(timeout=10)
    assert get_returncode == 0, f"get_links.sh failed: {get_stderr}"
    assert calc_proc.returncode == 0, f"calc_shortest_path.sh failed: {calc_proc.stderr}"

    content = read_plan()
    expected_content = (
        "Path: backup-01 -> relay-01 -> relay-02 -> db-target-01 | "
        "Total Latency: 30"
    )
    assert content == expected_content, (
        f"File {PLAN} content is incorrect. Expected '{expected_content}', "
        f"got '{content}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
