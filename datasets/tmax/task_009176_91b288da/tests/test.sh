#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import csv
import random
from collections import Counter
import pytest

DB_PATH = "/home/user/network.db"
CSV_PATH = "/home/user/top_users.csv"


def get_db_data():
    if not os.path.exists(DB_PATH):
        pytest.fail(f"Database file {DB_PATH} does not exist.")

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    cur.execute("SELECT user_id, username FROM users")
    users = {row[0]: row[1] for row in cur.fetchall()}

    cur.execute("SELECT follower_id, followee_id FROM follows")
    follows = set(cur.fetchall())

    cur.execute("SELECT follower_id, followee_id FROM active_follows")
    active_follows = set(cur.fetchall())

    conn.close()
    return users, follows, active_follows


def get_original_canonical_data():
    users = [(i, f"user_{i}") for i in range(1, 101)]

    random.seed(42)
    follows = set()
    while len(follows) < 500:
        u1 = random.randint(1, 100)
        u2 = random.randint(1, 100)
        if u1 != u2:
            follows.add((u1, u2, "2023-01-01 12:00:00"))

    return users, follows


def compute_expected_pagerank(users_dict, follows_set):
    nodes = list(users_dict.keys())
    N = len(nodes)
    if N == 0:
        return {}

    # Filter follows to only include existing users
    valid_edges = [(u, v) for u, v in follows_set if u in users_dict and v in users_dict]

    out_degree = {n: 0 for n in nodes}
    in_edges = {n: [] for n in nodes}
    for u, v in valid_edges:
        out_degree[u] += 1
        in_edges[v].append(u)

    dangling_nodes = [n for n in nodes if out_degree[n] == 0]

    alpha = 0.85
    max_iter = 100
    tol = 1.0e-6

    x = {n: 1.0 / N for n in nodes}

    for _ in range(max_iter):
        xlast = x.copy()
        danglesum = alpha * sum(xlast[n] for n in dangling_nodes)

        for n in nodes:
            s = sum(xlast[u] / out_degree[u] for u in in_edges[n])
            x[n] = danglesum / N + (1.0 - alpha) / N + alpha * s

        err = sum(abs(x[n] - xlast[n]) for n in nodes)
        if err < N * tol:
            break

    return x


def test_canonical_tables_unchanged():
    """Verify that the canonical users and follows rows were not modified."""
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."
    expected_users, expected_follows = get_original_canonical_data()

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("SELECT user_id, username FROM users ORDER BY user_id")
    actual_users = cur.fetchall()
    cur.execute("SELECT follower_id, followee_id, created_at FROM follows")
    actual_follows = cur.fetchall()
    conn.close()

    assert actual_users == expected_users, "Canonical users table was modified."
    assert Counter(actual_follows) == Counter(expected_follows), "Canonical follows table was modified."


def test_active_follows_cleaned():
    """Verify that active_follows contains no stale rows."""
    users, follows, active_follows = get_db_data()

    # Valid active_follows are those in follows where both users exist
    expected_active_follows = {(u, v) for u, v in follows if u in users and v in users}

    stale_rows = active_follows - expected_active_follows
    missing_rows = expected_active_follows - active_follows

    assert not stale_rows, f"Found stale rows in active_follows: {list(stale_rows)[:5]}..."
    assert not missing_rows, f"Missing valid rows in active_follows: {list(missing_rows)[:5]}..."


def test_csv_output():
    """Verify the CSV output for top PageRank users."""
    assert os.path.exists(CSV_PATH), f"CSV file {CSV_PATH} was not found."

    users, follows, _ = get_db_data()
    pr = compute_expected_pagerank(users, follows)

    # Sort and get top 5
    sorted_pr = sorted(pr.items(), key=lambda item: item[1], reverse=True)
    top_5 = sorted_pr[:5]

    expected_rows = []
    for user_id, score in top_5:
        username = users[user_id]
        expected_rows.append([str(user_id), username, f"{score:.4f}"])

    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "CSV file is empty."

    header = rows[0]
    assert header == ["user_id", "username", "pagerank"], f"Incorrect CSV header: {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 5, f"Expected exactly 5 data rows, found {len(data_rows)}"

    for i, (actual, expected) in enumerate(zip(data_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
