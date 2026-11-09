#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import re
import secrets
import sqlite3
import subprocess
from decimal import Decimal

import pytest

DB_PATH = '/home/user/retail.db'
SCRIPT_PATH = '/home/user/analyze.py'
INDEXES_PATH = '/home/user/indexes.sql'
OUTPUT_PATH = '/home/user/electronics_trailing_revenue.csv'
HEADER = ['product_id', 'product_name', 'sale_date', 'daily_revenue', 'trailing_7_sales_revenue']


def run_analyzer():
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'analyze.py failed with exit code {result.returncode}. '
        f'stdout: {result.stdout}\nstderr: {result.stderr}'
    )
    assert os.path.isfile(OUTPUT_PATH), f'Output file {OUTPUT_PATH} is missing.'


def table_columns(conn, table):
    return [row[1] for row in conn.execute(f'PRAGMA table_info("{table}")')]


def decimal_value(value):
    return Decimal(str(value))


def test_retail_db_exists():
    assert os.path.isfile(DB_PATH), f'Database file {DB_PATH} is missing.'


def test_database_contains_loaded_csv_data():
    assert os.path.isfile(DB_PATH), f'Database file {DB_PATH} is missing.'
    conn = sqlite3.connect(DB_PATH)
    try:
        assert table_columns(conn, 'categories') == ['category_id', 'category_name', 'parent_category_id']
        assert table_columns(conn, 'products') == ['product_id', 'category_id', 'product_name']
        assert table_columns(conn, 'sales') == ['sale_id', 'product_id', 'sale_date', 'quantity', 'price']

        categories = conn.execute(
            'SELECT category_id, category_name, parent_category_id FROM categories ORDER BY category_id'
        ).fetchall()
        normalized_categories = [
            (int(cid), name, None if parent in (None, '') else int(parent))
            for cid, name, parent in categories
        ]
        assert normalized_categories == [
            (1, 'All', None), (2, 'Electronics', 1), (3, 'Computers', 2),
            (4, 'Laptops', 3), (5, 'Phones', 2), (6, 'Clothing', 1),
        ]

        products = conn.execute(
            'SELECT product_id, category_id, product_name FROM products ORDER BY product_id'
        ).fetchall()
        assert [(int(a), int(b), c) for a, b, c in products] == [
            (101, 4, 'MacBook Pro'), (102, 5, 'iPhone 14'),
            (103, 6, 'T-Shirt'), (104, 3, 'Desktop PC'),
        ]

        sales = conn.execute(
            'SELECT sale_id, product_id, sale_date, quantity, price FROM sales ORDER BY sale_id'
        ).fetchall()
        expected = [
            (1,101,'2023-09-28',1,2000), (2,101,'2023-09-29',1,2000),
            (3,101,'2023-10-01',1,2000), (4,101,'2023-10-02',2,2000),
            (5,101,'2023-10-05',1,2000), (6,102,'2023-10-01',5,1000),
            (7,103,'2023-10-01',10,20), (8,104,'2023-10-15',1,1500),
            (9,101,'2023-10-20',1,2000),
        ]
        normalized_sales = [
            (int(a), int(b), c, decimal_value(d), decimal_value(e))
            for a, b, c, d, e in sales
        ]
        expected_normalized = [
            (a, b, c, Decimal(d), Decimal(e)) for a, b, c, d, e in expected
        ]
        assert normalized_sales == expected_normalized
    finally:
        conn.close()


def test_database_has_indexes():
    assert os.path.isfile(DB_PATH), f'Database file {DB_PATH} is missing.'
    conn = sqlite3.connect(DB_PATH)
    try:
        custom = conn.execute(
            "SELECT name, tbl_name FROM sqlite_master "
            "WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%'"
        ).fetchall()
        assert len(custom) > 0, 'No custom indexes found in the database.'

        index_columns = {}
        for name, table in custom:
            escaped = name.replace('"', '""')
            cols = [row[2].lower() for row in conn.execute(f'PRAGMA index_info("{escaped}")')]
            index_columns[(name, table.lower())] = cols

        assert any(table == 'categories' and cols[:1] == ['parent_category_id']
                   for (_, table), cols in index_columns.items()), \
            'A relevant index on categories(parent_category_id) is required.'
        assert any(table == 'products' and cols[:1] == ['category_id']
                   for (_, table), cols in index_columns.items()), \
            'A relevant index on products(category_id) is required.'
        assert any(table == 'sales' and cols[:2] == ['product_id', 'sale_date']
                   for (_, table), cols in index_columns.items()), \
            'A relevant index on sales(product_id, sale_date) is required.'
    finally:
        conn.close()


def test_indexes_sql_exists_and_records_created_indexes():
    assert os.path.isfile(INDEXES_PATH), f'SQL file {INDEXES_PATH} is missing.'
    sql = open(INDEXES_PATH, encoding='utf-8').read()
    assert re.search(r'\bCREATE\s+(?:UNIQUE\s+)?INDEX\b', sql, re.I), \
        'indexes.sql does not contain CREATE INDEX statements.'

    conn = sqlite3.connect(DB_PATH)
    try:
        relevant_names = []
        for name, table in conn.execute(
            "SELECT name, tbl_name FROM sqlite_master "
            "WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%'"
        ):
            escaped = name.replace('"', '""')
            cols = [row[2].lower() for row in conn.execute(f'PRAGMA index_info("{escaped}")')]
            if ((table.lower() == 'categories' and cols[:1] == ['parent_category_id']) or
                (table.lower() == 'products' and cols[:1] == ['category_id']) or
                (table.lower() == 'sales' and cols[:2] == ['product_id', 'sale_date'])):
                relevant_names.append(name)
        for name in relevant_names:
            assert re.search(r'\bCREATE\s+(?:UNIQUE\s+)?INDEX(?:\s+IF\s+NOT\s+EXISTS)?\s+["`\[]?'
                             + re.escape(name) + r'["`\]]?', sql, re.I), \
                f'Created index {name!r} is not recorded in indexes.sql.'
    finally:
        conn.close()


def resolve_string(node, constants):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return constants.get(node.id)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = resolve_string(node.left, constants)
        right = resolve_string(node.right, constants)
        if left is not None and right is not None:
            return left + right
    return None


def test_analyze_script_exists_and_uses_one_cte_window_query():
    assert os.path.isfile(SCRIPT_PATH), f'Python script {SCRIPT_PATH} is missing.'
    source = open(SCRIPT_PATH, encoding='utf-8').read()
    tree = ast.parse(source, filename=SCRIPT_PATH)
    constants = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value_node = node.value
            value = resolve_string(value_node, constants)
            if value is not None:
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                for target in targets:
                    if isinstance(target, ast.Name):
                        constants[target.id] = value

    calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if node.func.attr in ('execute', 'executemany', 'executescript'):
                calls.append(node)
    assert len(calls) == 1, 'analyze.py must execute a single SQL query.'
    assert calls[0].func.attr == 'execute', 'The analytical query must be executed as one query.'
    assert calls[0].args, 'The SQL execute call has no query argument.'
    query = resolve_string(calls[0].args[0], constants)
    assert query is not None, 'The single SQL query must be present in analyze.py.'
    upper = query.upper()
    assert re.search(r'\bWITH\b', upper), 'The analytical query must use CTEs.'
    assert re.search(r'\bRECURSIVE\b', upper), 'The category hierarchy must use a recursive CTE.'
    assert re.search(r'\bOVER\s*\(', upper), 'The analytical query must use a window function.'


def test_analyzer_runs_and_original_report_is_correct():
    run_analyzer()
    expected_rows = [
        HEADER,
        ['101', 'MacBook Pro', '2023-10-01', '2000', '6000'],
        ['101', 'MacBook Pro', '2023-10-02', '4000', '10000'],
        ['101', 'MacBook Pro', '2023-10-05', '2000', '12000'],
        ['101', 'MacBook Pro', '2023-10-20', '2000', '14000'],
        ['102', 'iPhone 14', '2023-10-01', '5000', '5000'],
        ['104', 'Desktop PC', '2023-10-15', '1500', '1500'],
    ]
    with open(OUTPUT_PATH, newline='', encoding='utf-8') as f:
        actual_rows = [[cell.strip() for cell in row] for row in csv.reader(f)]
    assert len(actual_rows) > 0, f'The file {OUTPUT_PATH} is empty.'
    assert actual_rows[0] == expected_rows[0], \
        f'Header row is incorrect. Expected {expected_rows[0]}, got {actual_rows[0]}'
    assert actual_rows == expected_rows, \
        f'The original report is incorrect. Expected {expected_rows}, got {actual_rows}'


def build_dynamic_fixture():
    token = secrets.token_hex(6)
    base = secrets.randbelow(50000) + 10000
    cats = [
        (base, 'Root_' + token, None),
        (base + 1, 'Electronics', base),
        (base + 2, 'Branch_' + token, base + 1),
        (base + 3, 'Deep_' + token, base + 2),
        (base + 4, 'Outside_' + token, base),
    ]
    products = [
        (base + 101, base + 3, 'DeepProduct_' + token),
        (base + 102, base + 1, 'DirectProduct_' + token),
        (base + 103, base + 4, 'ExcludedProduct_' + token),
    ]
    dates = ['2023-09-20','2023-09-22','2023-09-24','2023-09-26',
             '2023-10-01','2023-10-02','2023-10-03','2023-10-04',
             '2023-10-05','2023-10-08','2023-10-12','2023-10-20']
    sales = []
    sid = base + 1000
    for i, date in enumerate(dates):
        sales.append((sid, base + 101, date, (i % 4) + 1, 11 + (base % 7)))
        sid += 1
    # A second sale on one date verifies daily aggregation occurs before the window.
    sales.append((sid, base + 101, '2023-10-03', 3, 7 + (base % 5))); sid += 1
    sales.extend([
        (sid, base + 102, '2023-09-30', 2, 19 + (base % 11)),
        (sid + 1, base + 102, '2023-10-07', 4, 13 + (base % 9)),
        (sid + 2, base + 103, '2023-10-09', 99, 99),
    ])

    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executescript('''
            CREATE TABLE categories(category_id INTEGER, category_name TEXT, parent_category_id INTEGER);
            CREATE TABLE products(product_id INTEGER, category_id INTEGER, product_name TEXT);
            CREATE TABLE sales(sale_id INTEGER, product_id INTEGER, sale_date TEXT, quantity INTEGER, price NUMERIC);
        ''')
        conn.executemany('INSERT INTO categories VALUES (?,?,?)', cats)
        conn.executemany('INSERT INTO products VALUES (?,?,?)', products)
        conn.executemany('INSERT INTO sales VALUES (?,?,?,?,?)', sales)
        conn.commit()
    finally:
        conn.close()

    relevant = {base + 101, base + 102}
    names = {pid: name for pid, _, name in products}
    daily = {}
    for _, pid, date, quantity, price in sales:
        if pid in relevant:
            daily[(pid, date)] = daily.get((pid, date), Decimal(0)) + Decimal(quantity) * Decimal(price)
    expected = []
    for pid in sorted(relevant):
        rows = sorted((date, revenue) for (p, date), revenue in daily.items() if p == pid)
        for i, (date, revenue) in enumerate(rows):
            trailing = sum((r for _, r in rows[max(0, i - 6):i + 1]), Decimal(0))
            if '2023-10-01' <= date <= '2023-10-31':
                expected.append((pid, names[pid], date, revenue, trailing))
    return expected


def test_analyzer_on_unseen_dynamic_database():
    expected = build_dynamic_fixture()
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    run_analyzer()
    with open(OUTPUT_PATH, newline='', encoding='utf-8') as f:
        rows = [[cell.strip() for cell in row] for row in csv.reader(f)]
    assert rows and rows[0] == HEADER, f'Incorrect CSV header: {rows[0] if rows else None}'
    assert len(rows) - 1 == len(expected), \
        f'Expected {len(expected)} dynamic data rows, got {len(rows) - 1}'
    actual = []
    for row in rows[1:]:
        assert len(row) == 5, f'Incorrect CSV row width: {row}'
        actual.append((int(row[0]), row[1], row[2], Decimal(row[3]), Decimal(row[4])))
    assert actual == expected, f'Dynamic report is incorrect. Expected {expected}, got {actual}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
