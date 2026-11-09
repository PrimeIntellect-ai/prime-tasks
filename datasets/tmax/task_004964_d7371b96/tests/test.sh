#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import itertools
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
import tempfile


def test_optimize_sql_exists_and_valid():
    """Verify optimize.sql executes and creates an index covering purchase fields."""
    sql_path = '/home/user/optimize.sql'
    assert os.path.exists(sql_path), f"{sql_path} does not exist."

    with open(sql_path, 'r') as f:
        original_content = f.read()
    content = original_content.lower()

    # Preserve the original assertions.
    assert "create " in content and " index " in content, \
        f"{sql_path} must contain a CREATE INDEX statement."
    assert "json_extract" in content or "->>" in content or "->" in content, \
        f"{sql_path} must use JSON extraction functions or operators to index the JSON fields."

    fd, db_path = tempfile.mkstemp(suffix='.db')
    os.close(fd)
    try:
        conn = sqlite3.connect(db_path)
        conn.execute("CREATE TABLE documents (id INTEGER PRIMARY KEY, doc TEXT)")
        sample_docs = [
            {"type": "purchase", "user_id": "U1", "product_id": "P1"},
            {"type": "purchase", "user_id": "U2", "product_id": "P2"},
            {"type": "user", "user_id": "U1"},
        ]
        conn.executemany(
            "INSERT INTO documents(doc) VALUES (?)",
            [(json.dumps(doc),) for doc in sample_docs],
        )
        conn.commit()

        try:
            conn.executescript(original_content)
        except sqlite3.Error as exc:
            raise AssertionError(f"{sql_path} is not executable SQL: {exc}")

        indexes = [row[1] for row in conn.execute("PRAGMA index_list('documents')")]
        assert indexes, f"{sql_path} did not create an index on documents."

        # A suitable expression/partial index lets SQLite obtain the purchase
        # predicate and both projected fields from the index without evaluating
        # JSON extraction functions against the table at query time.
        query_forms = [
            (
                "json_extract(doc, '$.user_id')",
                "json_extract(doc, '$.product_id')",
                "json_extract(doc, '$.type')",
                "'purchase'",
            ),
            (
                "doc ->> '$.user_id'",
                "doc ->> '$.product_id'",
                "doc ->> '$.type'",
                "'purchase'",
            ),
            (
                "doc -> '$.user_id'",
                "doc -> '$.product_id'",
                "doc -> '$.type'",
                "'\"purchase\"'",
            ),
        ]

        suitable = False
        for index_name in indexes:
            quoted_index = '"' + index_name.replace('"', '""') + '"'
            for user_expr, product_expr, type_expr, purchase_value in query_forms:
                query = (
                    f"SELECT {user_expr}, {product_expr} "
                    f"FROM documents INDEXED BY {quoted_index} "
                    f"WHERE {type_expr} = {purchase_value}"
                )
                try:
                    plan = list(conn.execute("EXPLAIN " + query))
                    rows = list(conn.execute(query))
                except sqlite3.Error:
                    continue

                function_ops = [
                    row for row in plan
                    if str(row[1]).lower() in ('function', 'purefunc')
                ]
                if not function_ops and rows == [('U1', 'P1'), ('U2', 'P2')]:
                    suitable = True
                    break
            if suitable:
                break

        assert suitable, (
            f"{sql_path} must create an executable index that covers extracted "
            "user_id and product_id values and restricts or indexes type='purchase'."
        )
        conn.close()
    finally:
        if os.path.exists(db_path):
            os.remove(db_path)


def compute_expected(db_path):
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("SELECT doc FROM documents")

    user_purchases = {}
    for (doc_str,) in cur.fetchall():
        try:
            doc = json.loads(doc_str)
            if doc.get("type") == "purchase":
                uid = doc.get("user_id")
                pid = doc.get("product_id")
                if uid and pid:
                    user_purchases.setdefault(uid, set()).add(pid)
        except json.JSONDecodeError:
            continue
    conn.close()

    expected_pairs = []
    users = sorted(user_purchases)
    for u1, u2 in itertools.combinations(users, 2):
        if len(user_purchases[u1].intersection(user_purchases[u2])) == 3:
            expected_pairs.append(f"{u1},{u2}")
    return sorted(expected_pairs)


def read_output(out_path):
    with open(out_path, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def test_matching_users_output():
    """Preserve the original output check against the provided database."""
    db_path = '/home/user/data_lake.db'
    out_path = '/home/user/matching_users.txt'

    assert os.path.exists(db_path), f"{db_path} does not exist."
    assert os.path.exists(out_path), f"{out_path} does not exist."

    expected_pairs = compute_expected(db_path)
    actual_lines = read_output(out_path)
    assert actual_lines == expected_pairs, \
        f"Output in {out_path} is incorrect. Expected {expected_pairs}, but got {actual_lines}"


def test_pipeline_executes_and_processes_dynamic_database():
    """Run pipeline.py against fresh unpredictable data and verify graph matching."""
    pipeline_path = '/home/user/pipeline.py'
    db_path = '/home/user/data_lake.db'
    out_path = '/home/user/matching_users.txt'

    assert os.path.isfile(pipeline_path), f"{pipeline_path} does not exist or is not a file."

    backup_fd, backup_path = tempfile.mkstemp(suffix='.db')
    os.close(backup_fd)
    shutil.copy2(db_path, backup_path)

    token = secrets.token_hex(8)
    users = [f"U_{token}_{i}" for i in range(4)]
    products = [f"P_{token}_{i}" for i in range(8)]
    purchase_sets = {
        users[0]: {products[0], products[1], products[2], products[6]},
        users[1]: {products[0], products[1], products[2], products[7]},
        users[2]: {products[0], products[1], products[3]},
        users[3]: {products[0], products[1], products[2], products[6]},
    }

    docs = []
    docs.extend({"type": "user", "user_id": uid, "name": token} for uid in users)
    docs.extend({"type": "product", "product_id": pid} for pid in products)
    for uid, purchased in purchase_sets.items():
        for pid in purchased:
            docs.append({"type": "purchase", "user_id": uid, "product_id": pid})
    # Duplicate relationships must not inflate the shared-product count.
    docs.append({"type": "purchase", "user_id": users[0], "product_id": products[0]})
    docs.append({"type": "other", "user_id": users[0], "product_id": products[3]})

    try:
        conn = sqlite3.connect(db_path)
        conn.execute("DELETE FROM documents")
        conn.executemany(
            "INSERT INTO documents(doc) VALUES (?)",
            [(json.dumps(doc),) for doc in docs],
        )
        conn.commit()
        conn.close()

        expected_pairs = compute_expected(db_path)
        assert expected_pairs, "Internal verifier dataset unexpectedly has no matches."

        if os.path.exists(out_path):
            os.remove(out_path)

        result = subprocess.run(
            ['python3', pipeline_path],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"pipeline.py failed with exit code {result.returncode}. "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )
        assert os.path.exists(out_path), "pipeline.py did not create matching_users.txt."

        actual_lines = read_output(out_path)
        assert actual_lines == expected_pairs, (
            "pipeline.py did not extract and match the dynamic purchase graph correctly. "
            f"Expected {expected_pairs}, got {actual_lines}."
        )
    finally:
        for suffix in ('-wal', '-shm', '-journal'):
            sidecar = db_path + suffix
            if os.path.exists(sidecar):
                os.remove(sidecar)
        shutil.copy2(backup_path, db_path)
        os.remove(backup_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
