#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import sqlite3
import subprocess
import uuid

DB_PATH = '/home/user/backup_catalog.db'
SCRIPT_PATH = '/home/user/analyze_backups.py'
JSON_PATH = '/home/user/chain_sizes.json'
PLAN_PATH = '/home/user/query_plan.txt'


def expected_original_records():
    random.seed(42)
    records = []
    full_backups = []

    for i in range(1, 51):
        bid = f"full_{i}"
        status = 'success' if random.random() > 0.1 else 'failed'
        size = random.randint(1000000, 5000000)
        records.append((bid, None, 'full', status, size))
        if status == 'success':
            full_backups.append(bid)

    current_parents = list(full_backups)
    for depth in range(1, 10):
        next_parents = []
        for parent in current_parents:
            for j in range(random.randint(0, 3)):
                bid = f"inc_{depth}_{parent}_{j}"
                status = 'success' if random.random() > 0.15 else 'failed'
                size = random.randint(10000, 500000)
                records.append((bid, parent, 'incremental', status, size))
                next_parents.append(bid)
        current_parents = next_parents

    return records


def read_records(conn):
    return conn.execute('''
        SELECT backup_id, parent_id, backup_type, status, size_bytes
        FROM backups
        ORDER BY backup_id
    ''').fetchall()


def get_expected_chain_sizes(conn):
    rows = conn.execute('''
        WITH RECURSIVE backup_chain AS (
            SELECT backup_id, backup_id AS root_id, size_bytes
            FROM backups
            WHERE parent_id IS NULL AND status = 'success'

            UNION ALL

            SELECT b.backup_id, c.root_id, b.size_bytes
            FROM backups b
            JOIN backup_chain c ON b.parent_id = c.backup_id
            WHERE b.status = 'success'
        )
        SELECT root_id, SUM(size_bytes)
        FROM backup_chain
        GROUP BY root_id
    ''').fetchall()
    return {str(root): int(total) for root, total in rows}


def secondary_parent_indexes(conn):
    result = []
    indexes = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='backups'"
    ).fetchall()
    for (name,) in indexes:
        if name.startswith('sqlite_autoindex'):
            continue
        quoted = name.replace('"', '""')
        columns = [row[2] for row in conn.execute(f'PRAGMA index_info("{quoted}")')]
        if 'parent_id' in columns:
            result.append(name)
    return result


def load_json_sizes():
    assert os.path.exists(JSON_PATH), f"Output file {JSON_PATH} does not exist."
    with open(JSON_PATH, 'r', encoding='utf-8') as handle:
        value = json.load(handle)
    assert isinstance(value, dict), 'chain_sizes.json must contain a JSON object.'
    return {str(key): int(total) for key, total in value.items()}


def run_script():
    for path in (JSON_PATH, PLAN_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"analyze_backups.py failed with exit code {result.returncode}:\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def check_plan(index_names):
    assert os.path.exists(PLAN_PATH), f"Query plan file {PLAN_PATH} does not exist."
    with open(PLAN_PATH, 'r', encoding='utf-8') as handle:
        plan_text = handle.read().upper()

    # Preserve the original assertion and additionally require details expected
    # from the recursive query and a real submitted parent_id index.
    assert 'INDEX' in plan_text, (
        'The query plan does not seem to indicate index usage for the backups table.'
    )
    assert 'RECURSIVE' in plan_text, (
        'The plan does not contain the recursive step of the requested CTE.'
    )
    assert any(name.upper() in plan_text for name in index_names), (
        'The plan does not reference an actual secondary parent_id index.'
    )


def main():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} missing."
    assert os.path.isfile(SCRIPT_PATH), f"Python script {SCRIPT_PATH} is missing."

    with open(SCRIPT_PATH, 'r', encoding='utf-8') as handle:
        source = handle.read()
    assert re.search(r'\bWITH\s+RECURSIVE\b', source, re.IGNORECASE), (
        'analyze_backups.py does not contain a Recursive CTE.'
    )
    assert re.search(r'\bEXPLAIN\s+QUERY\s+PLAN\b', source, re.IGNORECASE), (
        'analyze_backups.py does not generate its plan with EXPLAIN QUERY PLAN.'
    )

    conn = sqlite3.connect(DB_PATH)
    try:
        schema = conn.execute('PRAGMA table_info(backups)').fetchall()
        assert [row[1] for row in schema] == [
            'backup_id', 'parent_id', 'backup_type', 'status', 'size_bytes'
        ], 'The backups table schema was modified.'

        canonical = sorted(expected_original_records(), key=lambda row: row[0])
        assert read_records(conn) == canonical, (
            'The original backup catalog rows were deleted or modified.'
        )

        index_names = secondary_parent_indexes(conn)
        assert index_names, (
            "No secondary index covering 'parent_id' was created on the backups table."
        )
    finally:
        conn.close()

    # Execute the submitted artifact rather than trusting pre-created outputs.
    run_script()
    conn = sqlite3.connect(DB_PATH)
    try:
        assert read_records(conn) == canonical, 'The analysis script modified backup data.'
        expected = get_expected_chain_sizes(conn)
        index_names = secondary_parent_indexes(conn)
    finally:
        conn.close()
    assert load_json_sizes() == expected, (
        'The calculated chain sizes in the JSON file do not match the expected values.'
    )
    check_plan(index_names)

    # Replace the rows with unpredictable verification-time data and execute the
    # script again, preventing hard-coded output for the shipped catalog.
    token = uuid.uuid4().hex
    root_a = f'full_a_{token}'
    root_b = f'full_b_{token}'
    failed_root = f'failed_full_{token}'
    child_a = f'inc_a_{token}'
    failed_child = f'inc_failed_{token}'
    blocked_grandchild = f'inc_blocked_{token}'
    valid_grandchild = f'inc_valid_{token}'
    child_b = f'inc_b_{token}'

    controlled = [
        (root_a, None, 'full', 'success', 101),
        (root_b, None, 'full', 'success', 211),
        (failed_root, None, 'full', 'failed', 307),
        (child_a, root_a, 'incremental', 'success', 13),
        (failed_child, root_a, 'incremental', 'failed', 17),
        (blocked_grandchild, failed_child, 'incremental', 'success', 19),
        (valid_grandchild, child_a, 'incremental', 'success', 23),
        (child_b, root_b, 'incremental', 'success', 29),
    ]

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('DELETE FROM backups')
        conn.executemany('INSERT INTO backups VALUES (?, ?, ?, ?, ?)', controlled)
        conn.commit()
    finally:
        conn.close()

    run_script()
    conn = sqlite3.connect(DB_PATH)
    try:
        expected_rows = sorted(controlled, key=lambda row: row[0])
        assert read_records(conn) == expected_rows, 'The analysis script modified test data.'
        expected = get_expected_chain_sizes(conn)
        index_names = secondary_parent_indexes(conn)
        assert index_names, (
            "No secondary index covering 'parent_id' remains on the backups table."
        )
    finally:
        conn.close()

    assert load_json_sizes() == expected, (
        'The script failed on verification-time backup chains, including failed ancestors.'
    )
    check_plan(index_names)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
