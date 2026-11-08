#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/find_mutual.sh"
DB_PATH = "/home/user/graph.db"
PLAN_PATH = "/home/user/query_plan.txt"


def run_script(target, limit, offset):
    try:
        result = subprocess.run(
            [SCRIPT_PATH, target, str(limit), str(offset)],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Script execution failed with error: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("Script execution timed out")
    return result.stdout.strip().splitlines()


def test_find_mutual_sh_output_1():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} not found."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    output = run_script("U1", 2, 0)
    expected = ["U7,3", "U5,2"]
    assert output == expected, f"Expected output {expected}, but got {output}"


def test_find_mutual_sh_output_2():
    output = run_script("U1", 2, 1)
    expected = ["U5,2", "U6,1"]
    assert output == expected, f"Expected output {expected}, but got {output}"


def get_custom_indexes(conn):
    rows = conn.execute(
        "SELECT name FROM sqlite_master "
        "WHERE type='index' AND tbl_name='edges' "
        "AND name NOT LIKE 'sqlite_autoindex%'"
    ).fetchall()
    return [row[0] for row in rows]


def canonical_plan(conn):
    sql = """
    EXPLAIN QUERY PLAN
    SELECT e2.source_id, COUNT(DISTINCT e2.target_id)
      FROM edges AS e1
      JOIN edges AS e2 ON e2.target_id = e1.target_id
      JOIN nodes AS n ON n.id = e2.source_id AND n.label = 'User'
     WHERE e1.source_id = 'U1'
       AND e1.rel_type = 'FOLLOWS'
       AND e2.rel_type = 'FOLLOWS'
       AND e2.source_id <> e1.source_id
     GROUP BY e2.source_id
     ORDER BY COUNT(DISTINCT e2.target_id) DESC, e2.source_id ASC
     LIMIT 10 OFFSET 0
    """
    return [row[3] for row in conn.execute(sql).fetchall()]


def test_indexes_created():
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} not found."

    conn = sqlite3.connect(DB_PATH)
    indexes = get_custom_indexes(conn)

    assert len(indexes) > 0, "No custom indexes found on the 'edges' table. You must create indexes to optimize the query."

    details = canonical_plan(conn)
    conn.close()

    used = [name for name in indexes if any(name.lower() in detail.lower() for detail in details)]
    assert used, (
        "The custom edges indexes are not used for the mutual-follow traversal. "
        f"Indexes: {indexes}; plan: {details}"
    )


def test_query_plan_exists_and_contains_index():
    assert os.path.exists(PLAN_PATH), f"File {PLAN_PATH} does not exist."
    assert os.path.isfile(PLAN_PATH), f"{PLAN_PATH} is not a file."

    with open(PLAN_PATH, 'r') as f:
        content = f.read().upper()

    assert content.strip() != "", f"File {PLAN_PATH} is empty."
    assert "INDEX" in content or "SEARCH" in content, f"query_plan.txt does not seem to contain an optimized query plan using indexes. Content: {content[:100]}..."

    conn = sqlite3.connect(DB_PATH)
    indexes = get_custom_indexes(conn)
    actual_details = canonical_plan(conn)
    conn.close()

    actually_used = {
        name for name in indexes
        if any(name.lower() in detail.lower() for detail in actual_details)
    }
    documented_and_used = {
        name for name in actually_used if name.upper() in content
    }
    assert documented_and_used, (
        "query_plan.txt must identify a real custom edges index that SQLite "
        "actually uses for the mutual-follow traversal. "
        f"Actual plan: {actual_details}"
    )
    assert re.search(r"\b(SEARCH|SCAN)\b.*\bEDGES\b", content), (
        "query_plan.txt does not contain an SQLite plan step for the edges table"
    )


def expected_from_database(target, limit, offset):
    conn = sqlite3.connect(DB_PATH)
    users = {
        row[0] for row in conn.execute(
            "SELECT id FROM nodes WHERE label = 'User'"
        )
    }
    follows = {}
    for source, destination in conn.execute(
        "SELECT source_id, target_id FROM edges WHERE rel_type = 'FOLLOWS'"
    ):
        follows.setdefault(source, set()).add(destination)
    conn.close()

    target_destinations = follows.get(target, set())
    rows = []
    for candidate in users:
        if candidate == target:
            continue
        count = len(target_destinations.intersection(follows.get(candidate, set())))
        if count:
            rows.append((candidate, count))
    rows.sort(key=lambda row: (-row[1], row[0]))
    return [f"{user_id},{count}" for user_id, count in rows[offset:offset + limit]]


def test_dynamic_graph_traversal_sorting_filtering_and_pagination():
    backup_fd, backup_path = tempfile.mkstemp(prefix="graph-backup-", suffix=".db")
    os.close(backup_fd)
    shutil.copy2(DB_PATH, backup_path)

    token = secrets.token_hex(8).upper()
    target1 = f"T_{token}_A"
    target2 = f"T_{token}_B"
    empty_target = f"T_{token}_EMPTY"
    destinations = [f"D_{token}_{i}" for i in range(5)]
    candidates = [f"C_{token}_{i}" for i in range(7)]
    bot = f"BOT_{token}"
    missing_source = f"MISSING_{token}"

    patterns = [
        [0, 1, 2, 3, 4],
        [0, 1, 2, 3],
        [0, 1, 2],
        [2, 3, 4],
        [0, 1],
        [3, 4],
        [4],
    ]

    try:
        conn = sqlite3.connect(DB_PATH)
        user_ids = [target1, target2, empty_target] + destinations + candidates
        conn.executemany(
            "INSERT INTO nodes(id, label) VALUES (?, 'User')",
            [(node_id,) for node_id in user_ids],
        )
        conn.execute("INSERT INTO nodes(id, label) VALUES (?, 'Service')", (bot,))

        edge_rows = []
        edge_rows.extend((target1, destination, "FOLLOWS") for destination in destinations)
        edge_rows.extend((target2, destinations[i], "FOLLOWS") for i in [1, 3, 4])
        for candidate, pattern in zip(candidates, patterns):
            edge_rows.extend(
                (candidate, destinations[i], "FOLLOWS") for i in pattern
            )

        # These rows ensure rel_type and User-node filtering are really applied.
        edge_rows.extend((bot, destination, "FOLLOWS") for destination in destinations)
        edge_rows.extend((missing_source, destination, "FOLLOWS") for destination in destinations)
        edge_rows.extend((candidates[-1], destination, "LIKES") for destination in destinations[:4])
        edge_rows.append((target1, f"NOISE_{token}", "LIKES"))

        conn.executemany(
            "INSERT INTO edges(source_id, target_id, rel_type) VALUES (?, ?, ?)",
            edge_rows,
        )
        conn.commit()
        conn.close()

        rng = random.SystemRandom()
        invocations = [(target1, 20, 0), (target2, 20, 0), (empty_target, 5, 0)]
        for target in [target1, target2]:
            for _ in range(5):
                invocations.append((target, rng.randint(1, 5), rng.randint(0, 8)))

        for target, limit, offset in invocations:
            expected = expected_from_database(target, limit, offset)
            output = run_script(target, limit, offset)
            assert output == expected, (
                f"For target={target!r}, limit={limit}, offset={offset}, "
                f"expected {expected}, but got {output}"
            )
    finally:
        shutil.copy2(backup_path, DB_PATH)
        os.unlink(backup_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
