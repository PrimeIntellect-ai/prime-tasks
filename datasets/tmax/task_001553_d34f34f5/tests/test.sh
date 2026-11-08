#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import sqlite3
import stat
import subprocess

SRC = "/home/user/etl_extract.c"
BIN = "/home/user/etl_extract"
DB = "/home/user/legacy.db"
OUT = "/home/user/graph_import.cypher"


def create_database(users, posts, connections):
    for suffix in ("", "-wal", "-shm", "-journal"):
        try:
            os.remove(DB + suffix)
        except FileNotFoundError:
            pass

    conn = sqlite3.connect(DB)
    conn.executescript("""
        CREATE TABLE t_alpha (a_id INTEGER PRIMARY KEY, a_name TEXT);
        CREATE TABLE t_beta (b_id INTEGER PRIMARY KEY, a_ref INTEGER, publish_date DATE);
        CREATE TABLE t_gamma (g_id INTEGER PRIMARY KEY, a_ref1 INTEGER, a_ref2 INTEGER);
    """)
    conn.executemany("INSERT INTO t_alpha VALUES (?, ?)", users)
    conn.executemany("INSERT INTO t_beta VALUES (?, ?, ?)", posts)
    conn.executemany("INSERT INTO t_gamma VALUES (?, ?, ?)", connections)
    conn.commit()
    conn.close()
    os.chmod(DB, 0o666)


def expected_lines(posts, connections):
    active = {
        user_id for _, user_id, publish_date in posts
        if publish_date > "2022-01-01"
    }
    pairs = sorted({
        (user1, user2) for _, user1, user2 in connections
        if user1 in active and user2 in active
    })
    return [
        f"CREATE (u1:User {{id: {user1}}})-[:CONNECTED_ACTIVE]->(u2:User {{id: {user2}}})"
        for user1, user2 in pairs
    ]


def execute_and_read():
    try:
        os.remove(OUT)
    except FileNotFoundError:
        pass
    subprocess.run([BIN], cwd="/home/user", check=True, timeout=20)
    assert os.path.isfile(OUT), f"Output file {OUT} is missing."
    with open(OUT, "r", encoding="utf-8") as f:
        return f.read().splitlines()


def assert_indexes_created_and_useful():
    assert os.path.isfile(DB), f"Database file {DB} is missing."
    conn = sqlite3.connect(DB)
    indexes = conn.execute(
        "SELECT name, tbl_name FROM sqlite_master WHERE type='index'"
    ).fetchall()
    user_indexes = [idx for idx in indexes if not idx[0].startswith("sqlite_")]

    # Preserve the original assertions.
    assert len(user_indexes) > 0, "No custom indexes were created in the database."
    indexed_tables = {idx[1] for idx in user_indexes}
    assert "t_beta" in indexed_tables or "t_gamma" in indexed_tables, (
        f"Expected indexes on t_beta or t_gamma, but found indexes on: {indexed_tables}"
    )

    columns_by_table = {"t_beta": set(), "t_gamma": set()}
    for index_name, table_name in user_indexes:
        if table_name in columns_by_table:
            safe_name = index_name.replace("'", "''")
            for row in conn.execute(f"PRAGMA index_info('{safe_name}')"):
                if row[2] is not None:
                    columns_by_table[table_name].add(row[2])
    conn.close()

    assert {"a_ref", "publish_date"}.issubset(columns_by_table["t_beta"]), (
        "Indexes on t_beta must cover both a_ref and publish_date; found indexed "
        f"columns {columns_by_table['t_beta']}"
    )
    assert {"a_ref1", "a_ref2"}.issubset(columns_by_table["t_gamma"]), (
        "Indexes on t_gamma must cover both connection columns; found indexed "
        f"columns {columns_by_table['t_gamma']}"
    )


def test_complete_etl_workflow():
    # Preserve the original source and executable existence assertions.
    assert os.path.isfile(SRC), f"C source file {SRC} is missing."
    assert os.path.isfile(BIN), f"Compiled binary {BIN} is missing."
    st = os.stat(BIN)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {BIN} is not executable."

    # Build the submitted source ourselves so the tested executable corresponds
    # to the required C artifact rather than an unrelated executable file.
    subprocess.run(
        ["gcc", "-std=c11", "-O2", SRC, "-o", BIN, "-lsqlite3"],
        check=True,
        timeout=30,
        capture_output=True,
        text=True,
    )

    # Confirm that the resulting program actually links to the SQLite C API.
    symbols = subprocess.run(
        ["nm", "-D", BIN], check=True, capture_output=True, text=True
    ).stdout
    assert re.search(r"\bsqlite3_open(?:_v2)?\b", symbols), (
        "The executable does not use sqlite3_open/sqlite3_open_v2."
    )
    assert re.search(r"\bsqlite3_(?:prepare_v2|exec)\b", symbols), (
        "The executable does not prepare or execute SQL through the SQLite C API."
    )
    assert re.search(r"\bsqlite3_close(?:_v2)?\b", symbols), (
        "The executable does not close its SQLite connection."
    )

    source_text = open(SRC, "r", encoding="utf-8", errors="replace").read().lower()
    assert "select" in source_text and "join" in source_text, (
        "The C source does not contain the required joined extraction query."
    )
    assert "exists" in source_text or source_text.count("select") >= 2, (
        "The extraction query does not contain a required subquery."
    )

    # Recreate and execute against the original fixture, preserving the original
    # exact output check while ensuring the submitted program produced the file.
    original_users = [
        (1, "Alice"), (2, "Bob"), (3, "Charlie"), (4, "David"), (5, "Eve")
    ]
    original_posts = [
        (101, 1, "2021-05-10"), (102, 1, "2022-03-15"),
        (103, 2, "2023-01-01"), (104, 3, "2021-12-31"),
        (105, 4, "2022-06-10"), (106, 5, "2023-11-11")
    ]
    original_connections = [
        (1001, 1, 2), (1002, 1, 3), (1003, 2, 4),
        (1004, 4, 5), (1005, 1, 5)
    ]
    create_database(original_users, original_posts, original_connections)
    actual = execute_and_read()
    expected = [
        "CREATE (u1:User {id: 1})-[:CONNECTED_ACTIVE]->(u2:User {id: 2})",
        "CREATE (u1:User {id: 1})-[:CONNECTED_ACTIVE]->(u2:User {id: 5})",
        "CREATE (u1:User {id: 2})-[:CONNECTED_ACTIVE]->(u2:User {id: 4})",
        "CREATE (u1:User {id: 4})-[:CONNECTED_ACTIVE]->(u2:User {id: 5})"
    ]
    assert actual == expected, f"Expected: {expected}\nActual: {actual}"
    assert_indexes_created_and_useful()

    # Exercise the executable on unpredictable replacement databases. Expected
    # answers are independently derived from the generated rows.
    rng = random.SystemRandom()
    for case in range(2):
        ids = rng.sample(range(20, 10000), 8)
        users = [(uid, f"user_{case}_{i}") for i, uid in enumerate(ids)]
        active = {ids[i] for i in ((0, 2, 3, 6) if case == 0 else (1, 4, 5, 7))}

        posts = []
        post_id = 20000 + case * 100
        for uid in ids:
            posts.append((post_id, uid, "2021-12-31"))
            post_id += 1
            if uid in active:
                posts.append((post_id, uid, rng.choice(["2022-01-02", "2023-07-19", "2025-04-03"])))
                post_id += 1
        # Boundary date is not strictly after the cutoff.
        posts.append((post_id, ids[-1], "2022-01-01"))

        raw_pairs = [
            (ids[6], ids[2]), (ids[0], ids[3]), (ids[4], ids[5]),
            (ids[2], ids[7]), (ids[1], ids[4]), (ids[3], ids[6]),
            (ids[5], ids[1]), (ids[7], ids[0]), (ids[2], ids[3])
        ]
        rng.shuffle(raw_pairs)
        connections = [
            (30000 + case * 100 + i, user1, user2)
            for i, (user1, user2) in enumerate(raw_pairs)
        ]

        create_database(users, posts, connections)
        actual = execute_and_read()
        expected = expected_lines(posts, connections)
        assert actual == expected, (
            f"Dynamic case {case} output mismatch.\nExpected: {expected}\nActual: {actual}"
        )
        assert_indexes_created_and_useful()


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
