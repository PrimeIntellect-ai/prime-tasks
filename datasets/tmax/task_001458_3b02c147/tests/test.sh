#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import sqlite3
import subprocess
import tempfile
import pytest

PACKAGE_DIR = '/app/sqlite-backup-validator-1.0'
MAKEFILE = os.path.join(PACKAGE_DIR, 'Makefile')
VALIDATOR = os.path.join(PACKAGE_DIR, 'validator.py')
DB_PATH = '/home/user/backup.db'
SUMMARY_PATH = '/home/user/validation_summary.json'
REQUIRED_KEYS = {'customer_id', 'customer_name', 'total_order_amount', 'total_items'}


def expected_rows(db_path):
    conn = sqlite3.connect(db_path)
    try:
        rows = conn.execute("""
            SELECT c.customer_id,
                   c.customer_name,
                   COALESCE((SELECT SUM(o.amount)
                             FROM orders o
                             WHERE o.customer_id = c.customer_id), 0),
                   COALESCE((SELECT COUNT(i.item_id)
                             FROM items i
                             JOIN orders o ON i.order_id = o.order_id
                             WHERE o.customer_id = c.customer_id), 0)
            FROM customers c
        """).fetchall()
    finally:
        conn.close()

    return {
        cid: {
            'customer_id': cid,
            'customer_name': name,
            'total_order_amount': round(float(amount), 2),
            'total_items': int(items),
        }
        for cid, name, amount, items in rows
    }


def load_and_check(path, expected):
    assert os.path.isfile(path), f'File not found: {path}'
    try:
        with open(path, 'r') as f:
            raw = json.load(f)
    except Exception as e:
        pytest.fail(f'Failed to read validator output: {e}')

    assert isinstance(raw, list), 'Output JSON must be a list.'
    assert all(isinstance(row, dict) for row in raw), 'Every output row must be a dictionary.'
    assert all(set(row) == REQUIRED_KEYS for row in raw), 'Each row must contain exactly the required keys.'
    assert all(isinstance(row['customer_id'], int) and not isinstance(row['customer_id'], bool) for row in raw)
    assert all(isinstance(row['customer_name'], str) for row in raw)
    assert all(isinstance(row['total_order_amount'], (int, float)) and not isinstance(row['total_order_amount'], bool) for row in raw)
    assert all(isinstance(row['total_items'], int) and not isinstance(row['total_items'], bool) for row in raw)

    ids = [row['customer_id'] for row in raw]
    assert len(ids) == len(set(ids)), 'Duplicate customer_id values are not allowed.'
    actual = {row['customer_id']: row for row in raw}
    assert set(actual) == set(expected), 'Output must contain exactly one row for every customer.'

    mae_sum = 0.0
    for cid, exp in expected.items():
        row = actual[cid]
        assert row['customer_name'] == exp['customer_name'], f'Incorrect customer_name for customer {cid}.'
        amount_diff = abs(exp['total_order_amount'] - float(row['total_order_amount']))
        items_diff = abs(exp['total_items'] - row['total_items'])
        mae_sum += amount_diff + items_diff
    mae = mae_sum / max(len(expected), 1)
    assert mae == 0.0, f'Expected MAE exactly 0.0, but got {mae}.'


def create_probe_db(path):
    rng = random.SystemRandom()
    base = rng.randrange(20000, 90000)
    conn = sqlite3.connect(path)
    try:
        conn.executescript('''
            CREATE TABLE customers (customer_id INTEGER PRIMARY KEY, customer_name TEXT);
            CREATE TABLE orders (order_id INTEGER PRIMARY KEY, customer_id INTEGER, amount REAL);
            CREATE TABLE items (item_id INTEGER PRIMARY KEY, order_id INTEGER, item_name TEXT);
        ''')
        order_id = base * 10
        for offset, item_counts in enumerate(([1, 4], [2, 3, 5], [6])):
            cid = base + offset
            conn.execute('INSERT INTO customers VALUES (?, ?)', (cid, f'Probe_{cid}'))
            for index, item_count in enumerate(item_counts):
                order_id += 1
                amount = round(rng.randrange(101, 9900) / 100.0, 2)
                conn.execute('INSERT INTO orders VALUES (?, ?, ?)', (order_id, cid, amount))
                for item_index in range(item_count):
                    conn.execute('INSERT INTO items (order_id, item_name) VALUES (?, ?)',
                                 (order_id, f'ProbeItem_{index}_{item_index}'))
        conn.commit()
    finally:
        conn.close()


def test_package_and_makefile_are_fixed_and_executable():
    assert os.path.isfile(MAKEFILE), f'Missing Makefile: {MAKEFILE}'
    assert os.path.isfile(VALIDATOR), f'Missing validator.py: {VALIDATOR}'

    with open(MAKEFILE, 'r') as f:
        makefile_text = f.read()
    recipe_lines = [line for line in makefile_text.splitlines() if line.startswith('\t')]
    assert any('validator.py' in line and re.search(r'\$(?:\(DB_PATH\)|\{DB_PATH\})', line)
               for line in recipe_lines), 'The validate recipe must pass DB_PATH to validator.py.'

    with open(VALIDATOR, 'r') as f:
        validator_text = f.read()
    assert re.search(r'\bJOIN\b', validator_text, re.IGNORECASE), 'validator.py must use explicit JOIN syntax.'
    assert not re.search(r'FROM\s+customers\s+(?:AS\s+)?\w+\s*,', validator_text, re.IGNORECASE), \
        'validator.py still contains an implicit comma join from customers.'

    fd, probe_db = tempfile.mkstemp(prefix='validator-probe-', suffix='.db')
    os.close(fd)
    os.unlink(probe_db)
    probe_out = probe_db + '.json'
    try:
        create_probe_db(probe_db)
        probe_expected = expected_rows(probe_db)

        subprocess.run(
            ['python3', VALIDATOR, '--db', probe_db, '--out', probe_out],
            cwd=PACKAGE_DIR, check=True, timeout=20
        )
        load_and_check(probe_out, probe_expected)

        if os.path.exists(SUMMARY_PATH):
            os.unlink(SUMMARY_PATH)
        subprocess.run(
            ['make', 'validate', f'DB_PATH={probe_db}'],
            cwd=PACKAGE_DIR, check=True, timeout=20
        )
        load_and_check(SUMMARY_PATH, probe_expected)
    finally:
        for path in (probe_db, probe_out):
            if os.path.exists(path):
                os.unlink(path)

    assert os.path.isfile(DB_PATH), f'The database at {DB_PATH} does not exist.'
    if os.path.exists(SUMMARY_PATH):
        os.unlink(SUMMARY_PATH)
    subprocess.run(
        ['make', 'validate', f'DB_PATH={DB_PATH}'],
        cwd=PACKAGE_DIR, check=True, timeout=20
    )


def test_validation_summary_exists():
    assert os.path.exists(SUMMARY_PATH), f'The output file {SUMMARY_PATH} does not exist.'


def test_validation_summary_metrics():
    assert os.path.isfile(SUMMARY_PATH), f'File not found: {SUMMARY_PATH}'
    assert os.path.exists(DB_PATH), f'The database at {DB_PATH} does not exist.'
    load_and_check(SUMMARY_PATH, expected_rows(DB_PATH))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
