#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import heapq
import os
import random
import re
import shutil
import sqlite3
import subprocess
import time
import pytest

DB = "/home/user/optimized.db"
SCRIPT = "/home/user/compute_path.sh"
REFERENCE = "/tests/ref_slow.py"
SOURCE_DB = "/app/network.db"


def qident(name):
    return '"' + name.replace('"', '""') + '"'


def run_agent(timeout=10):
    result = subprocess.run(
        ["bash", SCRIPT], capture_output=True, text=True, timeout=timeout
    )
    assert result.returncode == 0, f"Agent script failed: {result.stderr}"
    output = result.stdout.strip()
    assert re.fullmatch(r"-?[0-9]+", output), f"Agent script output is not a single integer: {result.stdout!r}"
    return int(output)


def graph_candidates(conn):
    candidates = []
    aliases = {
        "src": {"src", "source", "source_id", "from_node", "from_id"},
        "dst": {"dst", "target", "destination", "target_id", "to_node", "to_id"},
        "cost": {"cost", "weight", "distance"},
    }
    rows = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    ).fetchall()
    for (table,) in rows:
        columns = [r[1] for r in conn.execute(f"PRAGMA table_info({qident(table)})")]
        lower = {c.lower(): c for c in columns}
        found = {}
        for role, names in aliases.items():
            matches = [lower[n] for n in names if n in lower]
            if matches:
                found[role] = matches[0]
        if len(found) == 3:
            candidates.append((table, found["src"], found["dst"], found["cost"]))
    return candidates


def is_exact_materialization(conn, candidate):
    table, src, dst, cost = candidate
    submitted = (
        f"SELECT {qident(src)}, {qident(dst)}, {qident(cost)}, COUNT(*) "
        f"FROM {qident(table)} GROUP BY 1,2,3"
    )
    source = (
        "SELECT r.source, r.target, c.cost, COUNT(*) "
        "FROM source_db.raw_links r JOIN source_db.link_costs c USING(link_id) "
        "GROUP BY 1,2,3"
    )
    missing = conn.execute(f"SELECT * FROM ({source}) EXCEPT SELECT * FROM ({submitted}) LIMIT 1").fetchone()
    extra = conn.execute(f"SELECT * FROM ({submitted}) EXCEPT SELECT * FROM ({source}) LIMIT 1").fetchone()
    expected_count = conn.execute(
        "SELECT COUNT(*) FROM source_db.raw_links r JOIN source_db.link_costs c USING(link_id)"
    ).fetchone()[0]
    actual_count = conn.execute(f"SELECT COUNT(*) FROM {qident(table)}").fetchone()[0]
    return missing is None and extra is None and actual_count == expected_count


def has_source_index(conn, candidate):
    table, src, _, _ = candidate
    for index_row in conn.execute(f"PRAGMA index_list({qident(table)})"):
        index_name = index_row[1]
        columns = [r[2] for r in conn.execute(f"PRAGMA index_info({qident(index_name)})")]
        if columns and columns[0].lower() == src.lower():
            return True
    return False


def shortest_path(conn, candidate, start=1050, target=8920):
    table, src, dst, cost = candidate
    rows = conn.execute(
        f"SELECT {qident(src)}, {qident(dst)}, {qident(cost)} FROM {qident(table)}"
    )
    adjacency = {}
    for u, v, weight in rows:
        assert isinstance(u, int) and isinstance(v, int) and isinstance(weight, int)
        assert weight >= 0, "Shortest-path verification requires nonnegative costs"
        adjacency.setdefault(u, []).append((v, weight))

    distances = {start: 0}
    queue = [(0, start)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        if node == target:
            return distance
        for neighbor, weight in adjacency.get(node, ()):
            candidate_distance = distance + weight
            if candidate_distance < distances.get(neighbor, float("inf")):
                distances[neighbor] = candidate_distance
                heapq.heappush(queue, (candidate_distance, neighbor))
    return -1


def test_optimized_db_exists_and_is_sqlite():
    assert os.path.exists(DB), f"Optimized database {DB} is missing."
    assert os.path.isfile(DB), f"{DB} is not a file."
    with open(DB, "rb") as handle:
        assert handle.read(16) == b"SQLite format 3\x00", f"{DB} is not an SQLite database."


def test_compute_path_script_exists():
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} is missing."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."
    assert os.path.getsize(SCRIPT) > 0, f"{SCRIPT} is empty."
    assert os.path.exists(REFERENCE), "Verification reference is missing."
    with open(SCRIPT, "rb") as submitted, open(REFERENCE, "rb") as reference:
        assert submitted.read() != reference.read(), "Submitted script is byte-identical to the reference implementation."


def test_materialized_indexed_graph():
    conn = sqlite3.connect(DB)
    try:
        conn.execute("ATTACH DATABASE ? AS source_db", (SOURCE_DB,))
        exact = [c for c in graph_candidates(conn) if is_exact_materialization(conn, c)]
        assert exact, "No materialized clean graph table matches the joined raw_links/link_costs data."
        assert any(has_source_index(conn, c) for c in exact), "The materialized graph has no index beginning with its source-node column."
    finally:
        conn.close()


def test_performance_correctness_and_live_graph_computation():
    conn = sqlite3.connect(DB)
    try:
        conn.execute("ATTACH DATABASE ? AS source_db", (SOURCE_DB,))
        exact = [c for c in graph_candidates(conn) if is_exact_materialization(conn, c)]
        assert exact, "No exact materialized graph was found."
        expected = shortest_path(conn, exact[0])
    finally:
        conn.close()

    start = time.perf_counter()
    agent_cost = run_agent()
    agent_time = time.perf_counter() - start

    start = time.perf_counter()
    ref_res = subprocess.run(["python3", REFERENCE], capture_output=True, text=True, timeout=15)
    ref_time = time.perf_counter() - start
    assert ref_res.returncode == 0, f"Reference script failed: {ref_res.stderr}"
    try:
        ref_cost = int(ref_res.stdout.strip())
    except ValueError:
        pytest.fail(f"Reference output is not an integer: {ref_res.stdout!r}")

    assert expected == 142, f"Trusted graph produced unexpected shortest path {expected}."
    assert agent_cost == 142, f"Agent output {agent_cost} does not match the correct cost 142."
    assert ref_cost == 142, f"Reference output {ref_cost} does not match 142."
    speedup = ref_time / agent_time
    assert speedup >= 5.0, f"Speedup {speedup:.2f}x is less than 5.0x (agent {agent_time:.4f}s, reference {ref_time:.4f}s)."

    backup = DB + ".verifier-backup"
    shutil.copy2(DB, backup)
    try:
        conn = sqlite3.connect(DB)
        candidates = graph_candidates(conn)
        changed_tables = 0
        a, b, c = [random.SystemRandom().randint(11, 35) for _ in range(3)]
        for table, src, dst, cost in candidates:
            updates = [
                (a, 1050, 2000, 50),
                (b, 2000, 3000, 50),
                (c, 3000, 8920, 42),
            ]
            changed = 0
            for new_cost, u, v, old_cost in updates:
                cursor = conn.execute(
                    f"UPDATE {qident(table)} SET {qident(cost)}=? "
                    f"WHERE {qident(src)}=? AND {qident(dst)}=? AND {qident(cost)}=?",
                    (new_cost, u, v, old_cost),
                )
                changed += cursor.rowcount
            if changed >= 3:
                changed_tables += 1
        conn.commit()
        assert changed_tables > 0, "Could not modify the materialized graph for the live-computation test."
        dynamic_expected = shortest_path(conn, exact[0])
        conn.close()

        assert dynamic_expected != 142, "Dynamic graph challenge did not change the shortest path."
        dynamic_actual = run_agent()
        assert dynamic_actual == dynamic_expected, (
            f"After graph costs changed, script returned {dynamic_actual}, but the computed shortest path is {dynamic_expected}. "
            "The script must compute from optimized.db rather than print a fixed answer."
        )
    finally:
        if os.path.exists(backup):
            shutil.move(backup, DB)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
