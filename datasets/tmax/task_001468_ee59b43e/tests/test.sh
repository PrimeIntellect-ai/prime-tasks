#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import random
import re
import secrets
import sqlite3
import subprocess
import tempfile

import pytest


def run_python(script, *args):
    return subprocess.run(
        ["python3", script, *args],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_sanitizer_adversarial_corpus():
    sanitizer_path = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_path), f"Sanitizer script not found at {sanitizer_path}"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus dir missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus dir missing: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.json')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.json')]

    assert len(clean_files) > 0, "No clean corpus files found."
    assert len(evil_files) > 0, "No evil corpus files found."

    clean_failed = []
    for cf in clean_files:
        res = run_python(sanitizer_path, cf)
        if res.returncode != 0:
            clean_failed.append(os.path.basename(cf))

    evil_failed = []
    for ef in evil_files:
        res = run_python(sanitizer_path, ef)
        if res.returncode != 1:
            evil_failed.append(os.path.basename(ef))

    error_msg = []
    if clean_failed:
        error_msg.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        error_msg.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failed)}")

    assert not clean_failed and not evil_failed, " | ".join(error_msg)


def test_sanitizer_generated_inputs_and_output():
    sanitizer_path = "/home/user/sanitizer.py"
    assert os.path.isfile(sanitizer_path)

    token = secrets.token_hex(8)
    clean_cases = [
        [{"$match": {"status": {"$in": [token, "active"]}}}],
        [
            {"$match": {"region": token}},
            {"$lookup": {
                "from": "docs_" + token,
                "localField": "acct",
                "foreignField": "account_id",
                "as": "joined",
            }},
            {"$project": {"joined": 1}},
        ],
        [
            {"$group": {"_id": "$category", "count": {"$sum": 1}}},
            {"$sort": {"count": -1}},
        ],
    ]
    evil_cases = [
        [{"$match": {"enabled": True, "$where": "this.score > 7"}}],
        [{"$match": {"nested": {"$where": "return true"}}}],
        [{"$lookup": {
            "from": "users_" + token,
            "localField": "email",
            "foreignField": "email_" + token,
            "as": "matches",
        }}],
        [
            {"$lookup": {
                "from": "ok",
                "localField": "acct",
                "foreignField": "account_id",
                "as": "ok",
            }},
            {"$lookup": {
                "from": "bad",
                "localField": "other",
                "foreignField": "unindexed_" + token,
                "as": "bad",
            }},
        ],
    ]

    with tempfile.TemporaryDirectory(prefix="pipeline_inputs_") as tmp:
        cases = [(p, True) for p in clean_cases] + [(p, False) for p in evil_cases]
        random.SystemRandom().shuffle(cases)
        for index, (pipeline, accepted) in enumerate(cases):
            path = os.path.join(tmp, f"{secrets.token_hex(10)}_{index}.json")
            with open(path, "w") as f:
                json.dump(pipeline, f)
            result = run_python(sanitizer_path, path)
            expected_code = 0 if accepted else 1
            expected_output = "ACCEPT" if accepted else "REJECT"
            assert result.returncode == expected_code, (
                f"Wrong status for generated pipeline {pipeline}: {result.returncode}; "
                f"stderr={result.stderr!r}"
            )
            assert result.stdout.strip() == expected_output, (
                f"Expected {expected_output!r}, got {result.stdout.strip()!r}"
            )


def load_query():
    sql_path = "/home/user/fix_query.sql"
    assert os.path.isfile(sql_path), f"Fixed query SQL not found at {sql_path}"
    with open(sql_path, "r") as f:
        return f.read()


def test_fix_query_sql():
    query = load_query()

    # Ensure ROW_NUMBER is part of the submitted SQL rather than merely mentioned
    # in a comment or string literal.
    executable_sql = re.sub(r"/\*.*?\*/", " ", query, flags=re.S)
    executable_sql = re.sub(r"--[^\n]*", " ", executable_sql)
    executable_sql = re.sub(r"'(?:''|[^'])*'", "''", executable_sql)
    assert re.search(r"\bROW_NUMBER\s*\(", executable_sql, flags=re.I), \
        "fix_query.sql must apply a ROW_NUMBER window function"
    assert re.search(r"\bOVER\s*\(", executable_sql, flags=re.I), \
        "ROW_NUMBER must be used as a window function with OVER"

    conn = sqlite3.connect(":memory:")
    cursor = conn.cursor()
    cursor.execute("""
    CREATE TABLE users (
        user_id TEXT PRIMARY KEY,
        name TEXT
    );
    """)
    cursor.execute("""
    CREATE TABLE transactions (
        tx_id TEXT PRIMARY KEY,
        user_id TEXT,
        amount DECIMAL,
        transaction_date TIMESTAMP
    );
    """)

    cursor.execute("INSERT INTO users VALUES ('u1', 'Alice')")
    cursor.execute("INSERT INTO users VALUES ('u2', 'Bob')")
    cursor.execute("INSERT INTO transactions VALUES ('t1', 'u1', 100, '2023-01-01 10:00:00')")
    cursor.execute("INSERT INTO transactions VALUES ('t2', 'u1', 200, '2023-01-02 10:00:00')")
    cursor.execute("INSERT INTO transactions VALUES ('t3', 'u2', 50, '2023-01-01 10:00:00')")

    try:
        cursor.execute(query)
        results = cursor.fetchall()
    except Exception as e:
        pytest.fail(f"Execution of fix_query.sql failed: {e}")

    assert len(results) == 2, "Query should return exactly one transaction per user."

    alice_res = [r for r in results if r[0] == 'Alice']
    bob_res = [r for r in results if r[0] == 'Bob']

    assert len(alice_res) == 1, "Alice should have exactly one record."
    assert alice_res[0][1] == 200, "Alice's record should be the most recent transaction (amount 200)."
    assert len(bob_res) == 1, "Bob should have exactly one record."
    assert bob_res[0][1] == 50, "Bob's record should be his only transaction (amount 50)."
    conn.close()


def test_fix_query_generated_data():
    query = load_query()
    rng = random.SystemRandom()
    token = secrets.token_hex(5)

    conn = sqlite3.connect(":memory:")
    cursor = conn.cursor()
    cursor.execute("CREATE TABLE users (user_id TEXT PRIMARY KEY, name TEXT)")
    cursor.execute("""
        CREATE TABLE transactions (
            tx_id TEXT PRIMARY KEY,
            user_id TEXT,
            amount DECIMAL,
            transaction_date TIMESTAMP
        )
    """)

    expected = {}
    for user_index in range(5):
        user_id = f"uid_{token}_{user_index}"
        name = f"person_{token}_{user_index}"
        cursor.execute("INSERT INTO users VALUES (?, ?)", (user_id, name))

        tx_count = rng.randint(2, 5)
        base_amount = rng.randint(1000, 9000) + user_index * 100
        for tx_index in range(tx_count):
            amount = base_amount + tx_index * 7
            date = f"2025-{user_index + 1:02d}-{tx_index + 1:02d} 12:{tx_index:02d}:00"
            cursor.execute(
                "INSERT INTO transactions VALUES (?, ?, ?, ?)",
                (f"tx_{token}_{user_index}_{tx_index}", user_id, amount, date),
            )
            if tx_index == tx_count - 1:
                expected[name] = amount

    # A transaction with no matching user must not be joined to any user.
    cursor.execute(
        "INSERT INTO transactions VALUES (?, ?, ?, ?)",
        (f"orphan_{token}", f"missing_{token}", 999999, "2099-12-31 23:59:59"),
    )

    try:
        cursor.execute(query)
        rows = cursor.fetchall()
    except Exception as e:
        pytest.fail(f"Execution on generated relational data failed: {e}")

    assert len(rows) == len(expected), "Query must return one latest transaction per matched user"
    actual = {}
    for row in rows:
        assert len(row) >= 2, "Query must return user name and transaction amount"
        assert row[0] not in actual, f"User {row[0]!r} was returned more than once"
        actual[row[0]] = row[1]
    assert actual == expected, f"Incorrect join or latest-row selection: {actual!r} != {expected!r}"
    conn.close()


def test_graph_path_script():
    script_path = "/home/user/graph_path.py"
    assert os.path.isfile(script_path), f"Graph path script not found at {script_path}"

    res = run_python(script_path, "A", "F")
    assert res.returncode == 0, "graph_path.py failed to execute for A -> F"
    output = res.stdout.strip()
    assert output == "A,C,F", f"Expected path A,C,F but got {output}"

    res2 = run_python(script_path, "A", "G")
    assert res2.returncode == 0, "graph_path.py failed to execute for A -> G"
    output2 = res2.stdout.strip()
    assert output2 in ["A,C,E,G", "A,B,D,G"], f"Expected shortest path A->G but got {output2}"

    res3 = run_python(script_path, "F", "A")
    assert res3.returncode == 0, "graph_path.py failed to execute for F -> A"
    output3 = res3.stdout.strip()
    assert output3 == "NONE", f"Expected NONE but got {output3}"


def shortest_distance(graph, source, target):
    queue = collections.deque([(source, 0)])
    seen = {source}
    while queue:
        node, distance = queue.popleft()
        if node == target:
            return distance
        for neighbor in graph.get(node, []):
            if neighbor not in seen:
                seen.add(neighbor)
                queue.append((neighbor, distance + 1))
    return None


def assert_graph_result(graph, source, target, output):
    distance = shortest_distance(graph, source, target)
    if distance is None:
        assert output == "NONE", f"Expected no path from {source} to {target}, got {output!r}"
        return

    assert output != "NONE", f"A path exists from {source} to {target}"
    path = output.split(",")
    assert path[0] == source and path[-1] == target, f"Wrong path endpoints: {path!r}"
    assert len(path) - 1 == distance, f"Path is not shortest: {path!r}"
    for left, right in zip(path, path[1:]):
        assert right in graph.get(left, []), f"Non-edge {left!r}->{right!r} in output path"


def test_graph_path_generated_graphs():
    script_path = "/home/user/graph_path.py"
    graph_path = "/app/etl/referrals.json"
    assert os.path.isfile(script_path)
    assert os.path.isfile(graph_path)

    with open(graph_path, "rb") as f:
        original = f.read()

    rng = random.SystemRandom()
    try:
        for iteration in range(3):
            prefix = secrets.token_hex(4)
            nodes = [f"n_{prefix}_{i}" for i in range(11)]
            graph = {node: [] for node in nodes}

            # Directed backbone plus random shortcuts and a deliberately isolated node.
            for i in range(8):
                graph[nodes[i]].append(nodes[i + 1])
            graph[nodes[0]].append(nodes[3])
            graph[nodes[3]].append(nodes[7])
            graph[nodes[1]].append(nodes[6])
            for i in range(9):
                for j in range(9):
                    if i != j and rng.random() < 0.09 and nodes[j] not in graph[nodes[i]]:
                        graph[nodes[i]].append(nodes[j])

            with open(graph_path, "w") as f:
                json.dump(graph, f)

            pairs = [
                (nodes[0], nodes[8]),
                (nodes[1], nodes[7]),
                (nodes[4], nodes[0]),
                (nodes[9], nodes[0]),
                (nodes[0], nodes[10]),
            ]
            for _ in range(5):
                pairs.append((rng.choice(nodes), rng.choice(nodes)))

            for source, target in pairs:
                result = run_python(script_path, source, target)
                assert result.returncode == 0, (
                    f"graph_path.py failed for generated pair {source}->{target}: {result.stderr!r}"
                )
                assert_graph_result(graph, source, target, result.stdout.strip())
    finally:
        with open(graph_path, "wb") as f:
            f.write(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
