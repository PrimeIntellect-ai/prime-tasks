#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import math
import os
import random
import re
import runpy
import shutil
import sqlite3
import tempfile
import uuid

DB = '/home/user/store.db'
SCRIPT = '/home/user/analyze.py'
RESULTS = '/home/user/results.csv'
PLAN = '/home/user/plan.txt'


def expected_results(db_path):
    conn = sqlite3.connect(db_path)
    try:
        users = {r[0]: (r[1], r[2]) for r in conn.execute('SELECT id, name, status FROM users')}
        products = {r[0]: r[1] for r in conn.execute('SELECT id, category FROM products')}
        totals = {}
        for user_id, product_id, amount in conn.execute('SELECT user_id, product_id, amount FROM orders ORDER BY id'):
            user = users.get(user_id)
            if user and user[1] == 'active' and products.get(product_id) == 'electronics':
                totals[user[0]] = totals.get(user[0], 0.0) + float(amount)
        return totals
    finally:
        conn.close()


def read_and_check_csv(expected):
    assert os.path.isfile(RESULTS), f'Results file {RESULTS} is missing.'
    with open(RESULTS, newline='') as f:
        rows = list(csv.reader(f))

    assert len(rows) >= 3, 'Results CSV should have a header and at least 2 data rows.'
    assert rows[0] == ['name', 'total_spent'], 'CSV header is incorrect.'
    assert all(len(row) == 2 for row in rows[1:]), 'Every results row must have exactly two columns.'

    names = [row[0] for row in rows[1:]]
    assert len(names) == len(set(names)), 'Results CSV contains duplicate names.'
    assert set(names) == set(expected), 'Results CSV has missing or unexpected rows.'
    for name, value in rows[1:]:
        try:
            actual = float(value)
        except ValueError:
            raise AssertionError(f'Invalid total for {name}: {value!r}')
        assert math.isclose(actual, expected[name], rel_tol=1e-10, abs_tol=1e-8), \
            f'{name} total is incorrect: expected {expected[name]}, got {actual}'
    return {row[0]: float(row[1]) for row in rows[1:]}


def run_script_and_capture_query():
    captured = []
    original_connect = sqlite3.connect

    class CursorProxy:
        def __init__(self, cursor):
            self._cursor = cursor
        def execute(self, sql, *args, **kwargs):
            captured.append(str(sql))
            self._cursor.execute(sql, *args, **kwargs)
            return self
        def executemany(self, sql, *args, **kwargs):
            return self._cursor.executemany(sql, *args, **kwargs)
        def __iter__(self):
            return iter(self._cursor)
        def __getattr__(self, name):
            return getattr(self._cursor, name)

    class ConnectionProxy:
        def __init__(self, conn):
            self._conn = conn
        def cursor(self, *args, **kwargs):
            return CursorProxy(self._conn.cursor(*args, **kwargs))
        def execute(self, sql, *args, **kwargs):
            captured.append(str(sql))
            return self._conn.execute(sql, *args, **kwargs)
        def __enter__(self):
            self._conn.__enter__()
            return self
        def __exit__(self, *args):
            return self._conn.__exit__(*args)
        def __getattr__(self, name):
            return getattr(self._conn, name)

    def recording_connect(*args, **kwargs):
        return ConnectionProxy(original_connect(*args, **kwargs))

    sqlite3.connect = recording_connect
    try:
        runpy.run_path(SCRIPT, run_name='__main__')
    finally:
        sqlite3.connect = original_connect

    candidates = []
    for sql in captured:
        upper = sql.upper()
        if ('SELECT' in upper and 'SUM' in upper and 'USERS' in upper
                and 'ORDERS' in upper and 'PRODUCTS' in upper):
            candidates.append(sql)
    assert candidates, 'The script did not execute the required aggregate query.'
    return candidates[-1]


def sql_code_only(sql):
    out = []
    i = 0
    while i < len(sql):
        if sql.startswith('--', i):
            end = sql.find('\n', i + 2)
            i = len(sql) if end < 0 else end
        elif sql.startswith('/*', i):
            end = sql.find('*/', i + 2)
            i = len(sql) if end < 0 else end + 2
        elif sql[i] in "'\"":
            quote = sql[i]
            out.append(' ')
            i += 1
            while i < len(sql):
                if sql[i] == quote:
                    if i + 1 < len(sql) and sql[i + 1] == quote:
                        i += 2
                        continue
                    i += 1
                    break
                i += 1
        else:
            out.append(sql[i])
            i += 1
    return ''.join(out)


def check_explicit_join(query):
    code = sql_code_only(query).upper()
    assert len(re.findall(r'\bJOIN\b', code)) >= 2, \
        'The executed query must explicitly join users, orders, and products.'
    match = re.search(r'\bFROM\b(.*?)(?:\bWHERE\b|\bGROUP\s+BY\b|\bHAVING\b|\bORDER\s+BY\b|\bLIMIT\b|$)', code, re.S)
    assert match, 'Could not identify the FROM clause in the executed query.'
    assert ',' not in match.group(1), 'The executed query uses comma-separated tables.'
    assert re.search(r'\bGROUP\s+BY\b', code), 'The executed query does not GROUP BY user name.'
    assert re.search(r'\bSUM\s*\(', code), 'The executed query does not calculate SUM.'


def parse_plan(content):
    stripped = content.strip()
    try:
        value = ast.literal_eval(stripped)
        if isinstance(value, list) and all(isinstance(x, (tuple, list)) and len(x) == 4 for x in value):
            return [tuple(x) for x in value]
    except Exception:
        pass

    rows = []
    for line in stripped.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            value = ast.literal_eval(line)
            if isinstance(value, (tuple, list)) and len(value) == 4:
                rows.append(tuple(value))
                continue
        except Exception:
            pass
        parts = line.split('|', 3)
        if len(parts) == 4:
            try:
                rows.append((int(parts[0]), int(parts[1]), int(parts[2]), parts[3]))
                continue
            except ValueError:
                pass
        raise AssertionError(f'plan.txt contains a line that is not exact EXPLAIN QUERY PLAN output: {line!r}')
    return rows


def check_plan(query):
    assert os.path.isfile(PLAN), f'Query plan file {PLAN} is missing.'
    with open(PLAN) as f:
        content = f.read().strip()
    assert len(content) > 0, 'The plan.txt file is empty.'
    assert any(keyword in content.upper() for keyword in ['SCAN', 'SEARCH', 'LIST', 'COROUTINE', 'B-TREE']), \
        'The plan.txt file does not look like a valid EXPLAIN QUERY PLAN output.'

    conn = sqlite3.connect(DB)
    try:
        expected = [tuple(row) for row in conn.execute('EXPLAIN QUERY PLAN ' + query).fetchall()]
    finally:
        conn.close()
    assert parse_plan(content) == expected, 'plan.txt is not the exact EXPLAIN QUERY PLAN output for the executed query.'


def check_indexes():
    assert os.path.isfile(DB), f'Database file {DB} is missing.'
    conn = sqlite3.connect(DB)
    try:
        def indexed(table, column):
            for idx in conn.execute("PRAGMA index_list('%s')" % table).fetchall():
                escaped = idx[1].replace("'", "''")
                cols = [row[2] for row in conn.execute("PRAGMA index_info('%s')" % escaped).fetchall()]
                if column in cols:
                    return True
            return False
        assert indexed('users', 'status'), "Missing index on 'status' column in 'users' table."
        assert indexed('products', 'category'), "Missing index on 'category' column in 'products' table."
    finally:
        conn.close()


def install_random_fixture():
    token = uuid.uuid4().hex
    a = 'Active_' + token
    b = 'Other_' + token
    inactive = 'Inactive_' + token
    no_match = 'NoMatch_' + token
    base = random.SystemRandom().randint(10000, 1000000)
    conn = sqlite3.connect(DB)
    try:
        conn.execute('DELETE FROM orders')
        conn.execute('DELETE FROM products')
        conn.execute('DELETE FROM users')
        conn.executemany('INSERT INTO users(id,name,status) VALUES(?,?,?)', [
            (base + 1, a, 'active'), (base + 2, a, 'active'),
            (base + 3, b, 'active'), (base + 4, inactive, 'inactive'),
            (base + 5, no_match, 'active')])
        conn.executemany('INSERT INTO products(id,name,category) VALUES(?,?,?)', [
            (base + 11, 'DeviceA', 'electronics'),
            (base + 12, 'DeviceB', 'electronics'),
            (base + 13, 'Book', 'books')])
        conn.executemany('INSERT INTO orders(id,user_id,product_id,amount) VALUES(?,?,?,?)', [
            (base + 21, base + 1, base + 11, 17.25),
            (base + 22, base + 1, base + 12, 3.0),
            (base + 23, base + 2, base + 11, 41.5),
            (base + 24, base + 2, base + 13, 900.0),
            (base + 25, base + 3, base + 12, 8.75),
            (base + 26, base + 4, base + 11, 700.0),
            (base + 27, base + 5, base + 13, 600.0)])
        conn.commit()
    finally:
        conn.close()


def test_complete_workflow():
    assert os.path.isfile(SCRIPT), f'Python script {SCRIPT} is missing.'

    # Preserve the original result assertions and reject extra/duplicate rows.
    initial = read_and_check_csv(expected_results(DB))
    assert 'Alice' in initial, "Alice's results are missing."
    assert initial['Alice'] == 1050.0, f"Alice's total spent is incorrect. Expected 1050.0, got {initial['Alice']}"
    assert 'Bob' in initial, "Bob's results are missing."
    assert initial['Bob'] == 1000.0, f"Bob's total spent is incorrect. Expected 1000.0, got {initial['Bob']}"

    with open(SCRIPT) as f:
        source = f.read().upper()
    assert ' JOIN ' in source, 'The query does not seem to use explicit JOIN syntax.'

    check_indexes()
    query = run_script_and_capture_query()
    check_explicit_join(query)
    read_and_check_csv(expected_results(DB))
    check_plan(query)

    fd, backup_path = tempfile.mkstemp(suffix='.db')
    os.close(fd)
    backup = sqlite3.connect(backup_path)
    live = sqlite3.connect(DB)
    live.backup(backup)
    live.close()
    backup.close()
    try:
        install_random_fixture()
        random_query = run_script_and_capture_query()
        check_explicit_join(random_query)
        read_and_check_csv(expected_results(DB))
    finally:
        saved = sqlite3.connect(backup_path)
        live = sqlite3.connect(DB)
        saved.backup(live)
        live.close()
        saved.close()
        os.unlink(backup_path)
        run_script_and_capture_query()

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
