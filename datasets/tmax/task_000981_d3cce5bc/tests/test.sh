#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import runpy
import sqlite3
import subprocess
import sys
import uuid
from collections import deque

import pytest

SCRIPT_PATH = "/home/user/etl_pipeline.py"
DB_PATH = "/home/user/ecommerce.db"
REPORT_PATH = "/home/user/final_report.json"


def get_expected_data():
    assert os.path.exists(DB_PATH), "Database file is missing."

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # Build graph
    c.execute("SELECT referrer_id, referred_id FROM referrals")
    referrals = c.fetchall()

    graph = {}
    for u, v in referrals:
        if u not in graph:
            graph[u] = []
        graph[u].append(v)

    # BFS to find users within 2 hops from user 1
    queue = deque([(1, 0)])
    visited = {1}
    valid_users = {1}

    while queue:
        curr, dist = queue.popleft()
        if dist < 2:
            for neighbor in graph.get(curr, []):
                if neighbor not in visited:
                    visited.add(neighbor)
                    valid_users.add(neighbor)
                    queue.append((neighbor, dist + 1))

    # Query expected sums
    placeholders = ",".join(["?"] * len(valid_users))
    query = f"""
        SELECT u.id, u.name, ROUND(SUM(t.amount), 2)
        FROM users u
        INNER JOIN transactions t ON u.id = t.user_id
        WHERE u.id IN ({placeholders})
        GROUP BY u.id, u.name
        ORDER BY u.id ASC
    """
    c.execute(query, list(valid_users))
    results = c.fetchall()
    conn.close()

    expected_output = []
    for row in results:
        expected_output.append({
            "user_id": row[0],
            "name": row[1],
            "total_spent": row[2]
        })

    return expected_output, valid_users


def assert_report_matches_expected():
    assert os.path.exists(REPORT_PATH), f"Expected report file {REPORT_PATH} was not found."

    with open(REPORT_PATH, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file final_report.json does not contain valid JSON.")

    expected_data, valid_users = get_expected_data()

    assert isinstance(actual_data, list), "The report must be a JSON list."
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} records, found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual.get("user_id") == expected["user_id"], f"Record {i} user_id mismatch: expected {expected['user_id']}, got {actual.get('user_id')}"
        assert actual.get("name") == expected["name"], f"Record {i} name mismatch: expected {expected['name']}, got {actual.get('name')}"
        assert isinstance(actual.get("total_spent"), float), f"Record {i} total_spent should be a float."
        assert abs(actual.get("total_spent") - expected["total_spent"]) < 0.01, f"Record {i} total_spent mismatch: expected {expected['total_spent']}, got {actual.get('total_spent')}"

    return valid_users


def install_randomized_database():
    rng = random.SystemRandom()
    ids = rng.sample(range(1000, 9000), 9)
    level1_a, level1_b, level2_a, level2_b, level2_c, level3, reverse_only, disconnected, extra = ids

    users = [1] + ids
    token = uuid.uuid4().hex[:10]

    referrals = [
        (1, level1_a),
        (1, level1_b),
        (level1_a, level2_a),
        (level1_a, level2_b),
        (level1_b, level2_c),
        (level2_a, level3),       # Three hops: must be excluded.
        (reverse_only, 1),        # Wrong direction: must be excluded.
        (disconnected, extra),
        (level2_b, level1_a),     # Cycle.
    ]

    reachable = {1, level1_a, level1_b, level2_a, level2_b, level2_c}
    no_transaction_user = level2_b
    transactions = []
    transaction_id = 1
    for user_id in users:
        if user_id == no_transaction_user:
            continue
        count = 2 if user_id in reachable else 1
        for _ in range(count):
            amount = rng.randint(1001, 9999) / 100.0
            transactions.append((transaction_id, user_id, amount))
            transaction_id += 1

    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")
    c.execute("CREATE TABLE transactions (id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL)")
    c.execute("CREATE TABLE referrals (referrer_id INTEGER, referred_id INTEGER)")
    c.executemany("INSERT INTO users VALUES (?, ?)", [(i, f"Random_{token}_{i}") for i in users])
    c.executemany("INSERT INTO transactions VALUES (?, ?, ?)", transactions)
    c.executemany("INSERT INTO referrals VALUES (?, ?)", referrals)
    conn.commit()
    conn.close()


class CursorProxy:
    def __init__(self, cursor, log):
        object.__setattr__(self, "_cursor", cursor)
        object.__setattr__(self, "_log", log)

    def execute(self, sql, *args, **kwargs):
        if args:
            params = args[0]
        else:
            params = kwargs.get("parameters", None)
        self._log.append((str(sql), params))
        return self._cursor.execute(sql, *args, **kwargs)

    def executemany(self, sql, seq, *args, **kwargs):
        self._log.append((str(sql), seq))
        return self._cursor.executemany(sql, seq, *args, **kwargs)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

    def __setattr__(self, name, value):
        setattr(self._cursor, name, value)

    def __iter__(self):
        return iter(self._cursor)


class ConnectionProxy:
    def __init__(self, conn, log):
        object.__setattr__(self, "_conn", conn)
        object.__setattr__(self, "_log", log)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._conn.cursor(*args, **kwargs), self._log)

    def execute(self, sql, *args, **kwargs):
        if args:
            params = args[0]
        else:
            params = kwargs.get("parameters", None)
        self._log.append((str(sql), params))
        return self._conn.execute(sql, *args, **kwargs)

    def __getattr__(self, name):
        return getattr(self._conn, name)

    def __setattr__(self, name, value):
        setattr(self._conn, name, value)

    def __enter__(self):
        self._conn.__enter__()
        return self

    def __exit__(self, *args):
        return self._conn.__exit__(*args)


def flatten_params(params):
    if params is None or isinstance(params, (str, bytes)):
        return []
    if isinstance(params, dict):
        return list(params.values())
    try:
        return list(params)
    except TypeError:
        return [params]


def test_final_report_exists_and_correct():
    assert os.path.exists(SCRIPT_PATH), f"Script file {SCRIPT_PATH} is missing."
    assert os.path.exists(DB_PATH), "Database file is missing."

    original_db = open(DB_PATH, "rb").read()
    original_report = open(REPORT_PATH, "rb").read() if os.path.exists(REPORT_PATH) else None

    try:
        install_randomized_database()
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)

        result = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"etl_pipeline.py failed when executed:\n{result.stderr}"
        valid_users = assert_report_matches_expected()

        # Execute the submitted artifact again while recording its real SQL calls.
        sql_log = []
        real_connect = sqlite3.connect

        def recording_connect(*args, **kwargs):
            return ConnectionProxy(real_connect(*args, **kwargs), sql_log)

        sqlite3.connect = recording_connect
        try:
            runpy.run_path(SCRIPT_PATH, run_name="__main__")
        finally:
            sqlite3.connect = real_connect

        assert_report_matches_expected()

        normalized = [(" ".join(sql.upper().split()), params) for sql, params in sql_log]
        referral_queries = [sql for sql, _ in normalized if "SELECT" in sql and "REFERRALS" in sql]
        assert referral_queries, "The executed pipeline did not load the referrals table for graph traversal."

        aggregate_queries = [
            (sql, params) for sql, params in normalized
            if "SELECT" in sql and "USERS" in sql and "TRANSACTIONS" in sql and "SUM" in sql
        ]
        assert aggregate_queries, "The executed pipeline did not run the required users/transactions aggregate query."

        matching_parameterized_query = False
        for sql, params in aggregate_queries:
            assert " JOIN " in f" {sql} ", "The aggregate query does not explicitly join users and transactions."
            assert " ON " in f" {sql} ", "The aggregate query is missing a join condition."
            assert "?" in sql, "The executed aggregate query is not parameterized with '?' placeholders."
            values = flatten_params(params)
            assert values, "The aggregate query was executed without a parameter sequence."
            try:
                parameter_ids = {int(value) for value in values}
            except (TypeError, ValueError):
                parameter_ids = set()
            if parameter_ids == set(valid_users) and sql.count("?") == len(values):
                matching_parameterized_query = True

        assert matching_parameterized_query, "The filtered graph user IDs were not passed as parameters to the joined aggregate query."
    finally:
        with open(DB_PATH, "wb") as f:
            f.write(original_db)
        if original_report is None:
            if os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)
        else:
            with open(REPORT_PATH, "wb") as f:
                f.write(original_report)


def test_script_uses_parameterized_queries():
    script_path = "/home/user/etl_pipeline.py"
    assert os.path.exists(script_path), f"Script file {script_path} is missing."

    with open(script_path, "r") as f:
        content = f.read()

    # Preserve the original source-level assertions in addition to runtime checks.
    assert "?" in content, "The script does not appear to use parameterized queries (missing '?')."
    assert "user_ids_str" not in content or "f\"\"\"" not in content or "{user_ids_str}" not in content, "The script still uses unsafe string formatting for the SQL query."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
