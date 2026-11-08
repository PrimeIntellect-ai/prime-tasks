#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
import pytest

DB_PATH = '/home/user/ecommerce.db'
OUTPUT_PATH = '/home/user/output.json'
EXPORT_PATH = '/home/user/export.py'
OPTIMIZE_PATH = '/home/user/optimize.sql'

EXPECTED_SCHEMA = {
    'users': [('id', 'INTEGER', 1), ('name', 'TEXT', 0), ('email', 'TEXT', 0)],
    'products': [('id', 'INTEGER', 1), ('name', 'TEXT', 0), ('category', 'TEXT', 0), ('price', 'REAL', 0)],
    'orders': [('id', 'INTEGER', 1), ('user_id', 'INTEGER', 0), ('order_date', 'TEXT', 0)],
    'order_items': [('id', 'INTEGER', 1), ('order_id', 'INTEGER', 0), ('product_id', 'INTEGER', 0), ('quantity', 'INTEGER', 0)],
}

EXPECTED_ROWS = {
    'users': [
        (1, 'Alice Smith', 'alice@example.com'),
        (2, 'Bob Jones', 'bob@example.com'),
        (3, 'Charlie Brown', 'charlie@example.com'),
    ],
    'products': [
        (1, 'Laptop', 'Electronics', 999.99),
        (2, 'Smartphone', 'Electronics', 599.99),
        (3, 'Novel', 'Books', 14.99),
        (4, 'T-Shirt', 'Clothing', 19.99),
        (5, 'Headphones', 'Electronics', 149.99),
    ],
    'orders': [
        (1, 1, '2023-05-14'),
        (2, 2, '2023-08-22'),
        (3, 1, '2022-11-05'),
        (4, 3, '2023-12-01'),
        (5, 2, '2023-01-15'),
    ],
    'order_items': [
        (1, 1, 1, 1),
        (2, 1, 5, 2),
        (3, 2, 2, 1),
        (4, 3, 3, 5),
        (5, 4, 1, 2),
        (6, 4, 4, 3),
        (7, 5, 5, 1),
    ],
}

MANDATED_OUTPUT = [
    {'user_name': 'Bob Jones', 'email': 'bob@example.com', 'order_date': '2023-01-15', 'product_name': 'Headphones', 'quantity': 1},
    {'user_name': 'Alice Smith', 'email': 'alice@example.com', 'order_date': '2023-05-14', 'product_name': 'Headphones', 'quantity': 2},
    {'user_name': 'Alice Smith', 'email': 'alice@example.com', 'order_date': '2023-05-14', 'product_name': 'Laptop', 'quantity': 1},
    {'user_name': 'Bob Jones', 'email': 'bob@example.com', 'order_date': '2023-08-22', 'product_name': 'Smartphone', 'quantity': 1},
    {'user_name': 'Charlie Brown', 'email': 'charlie@example.com', 'order_date': '2023-12-01', 'product_name': 'Laptop', 'quantity': 2},
]

CREATE_SCHEMA = '''
CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT);
CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, category TEXT, price REAL);
CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER, order_date TEXT);
CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER, product_id INTEGER, quantity INTEGER);
'''


def assert_database_pristine():
    assert os.path.isfile(DB_PATH), f'Database file {DB_PATH} is missing.'
    conn = sqlite3.connect(DB_PATH)
    try:
        for table, expected_columns in EXPECTED_SCHEMA.items():
            row = conn.execute("SELECT type FROM sqlite_master WHERE name = ?", (table,)).fetchone()
            assert row == ('table',), f'{table} must remain a table.'
            columns = [(r[1], r[2].upper(), r[5]) for r in conn.execute(f'PRAGMA table_info({table})')]
            assert columns == expected_columns, f'The schema of {table} was modified: {columns}'
            actual = conn.execute(f'SELECT * FROM {table} ORDER BY id').fetchall()
            assert actual == EXPECTED_ROWS[table], f'The original rows in {table} were modified or removed.'
    finally:
        conn.close()


def index_columns(conn):
    result = []
    indexes = conn.execute(
        "SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
    ).fetchall()
    for name, table in indexes:
        quoted = name.replace("'", "''")
        cols = [row[2] for row in conn.execute(f"PRAGMA index_info('{quoted}')") if row[2] is not None]
        result.append((name, table, cols))
    return result


def assert_useful_indexes(conn):
    indexes = index_columns(conn)
    assert len(indexes) >= 4, f'Expected at least 4 secondary indexes to be created, but found {len(indexes)}: {indexes}'
    covered = {(table, column) for _, table, columns in indexes for column in columns}
    required = {
        ('orders', 'user_id'),
        ('order_items', 'order_id'),
        ('order_items', 'product_id'),
        ('products', 'category'),
        ('orders', 'order_date'),
    }
    missing = required - covered
    assert not missing, f'Missing indexes covering required join/filter columns: {sorted(missing)}. Found: {indexes}'


def read_json_output():
    assert os.path.exists(OUTPUT_PATH), f'Output file {OUTPUT_PATH} was not found.'
    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {OUTPUT_PATH} does not contain valid JSON.')
    assert isinstance(data, list), f'Expected the JSON output to be a list of objects, got {type(data).__name__}.'
    return data


def test_database_was_not_modified_to_fake_results():
    assert_database_pristine()


def test_required_artifacts_exist():
    for path in (EXPORT_PATH, OPTIMIZE_PATH):
        assert os.path.isfile(path), f'Required file {path} is missing or is not a regular file.'
        assert os.path.getsize(path) > 0, f'Required file {path} is empty.'


def test_indexes_created():
    """Verify that at least 4 secondary indexes were created in the database."""
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    try:
        assert_useful_indexes(conn)
    finally:
        conn.close()


def test_optimize_script_itself_creates_the_required_indexes():
    with open(OPTIMIZE_PATH, 'r', encoding='utf-8') as f:
        sql = f.read()
    assert re.search(r'\bCREATE\s+(?:UNIQUE\s+)?INDEX\b', sql, re.IGNORECASE), 'optimize.sql contains no CREATE INDEX statement.'
    fd, path = tempfile.mkstemp(suffix='.db')
    os.close(fd)
    try:
        conn = sqlite3.connect(path)
        try:
            conn.executescript(CREATE_SCHEMA)
            conn.executescript(sql)
            assert_useful_indexes(conn)
            for table in EXPECTED_SCHEMA:
                assert conn.execute("SELECT type FROM sqlite_master WHERE name=?", (table,)).fetchone() == ('table',)
        finally:
            conn.close()
    finally:
        os.unlink(path)


def test_output_json_correct():
    """Verify that output.json exists, is valid JSON, and contains the correct sorted data."""
    actual_data = read_json_output()

    # Preserve the original database-derived assertion after first verifying that
    # the database still contains the immutable fixture data.
    assert_database_pristine()
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        query = '''
            SELECT u.name AS user_name, u.email, o.order_date,
                   p.name AS product_name, oi.quantity
            FROM orders o
            JOIN users u ON o.user_id = u.id
            JOIN order_items oi ON o.id = oi.order_id
            JOIN products p ON oi.product_id = p.id
            WHERE p.category = ? AND o.order_date BETWEEN ? AND ?
            ORDER BY o.order_date ASC, p.name ASC, u.name ASC
        '''
        expected_data = [dict(row) for row in conn.execute(query, ('Electronics', '2023-01-01', '2023-12-31')).fetchall()]
    finally:
        conn.close()

    assert actual_data == expected_data, (
        'The contents of output.json do not match the expected query results. '
        'Ensure you are joining the correct tables, filtering by the exact category and date range, '
        'and sorting by order_date ASC, product_name ASC, user_name ASC.'
    )
    assert actual_data == MANDATED_OUTPUT


def test_export_uses_parameterized_sql():
    source = open(EXPORT_PATH, 'r', encoding='utf-8').read()
    try:
        tree = ast.parse(source, EXPORT_PATH)
    except SyntaxError as exc:
        pytest.fail(f'export.py is not valid Python: {exc}')

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    assignments[target.id] = node.value

    def resolve(node):
        seen = set()
        while isinstance(node, ast.Name) and node.id in assignments and node.id not in seen:
            seen.add(node.id)
            node = assignments[node.id]
        return node

    parameterized_select = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute) or node.func.attr != 'execute' or not node.args:
            continue
        query_node = resolve(node.args[0])
        assert not isinstance(query_node, (ast.JoinedStr, ast.BinOp)), 'SQL passed to execute() must not be constructed with interpolation or concatenation.'
        assert not (isinstance(query_node, ast.Call) and isinstance(query_node.func, ast.Attribute) and query_node.func.attr == 'format'), 'SQL passed to execute() must not use str.format().'
        if isinstance(query_node, ast.Constant) and isinstance(query_node.value, str) and re.search(r'\bSELECT\b', query_node.value, re.I):
            has_placeholder = '?' in query_node.value or re.search(r'(?<!:):[A-Za-z_]\w*', query_node.value)
            if len(node.args) >= 2 and has_placeholder:
                parameterized_select = True
    assert parameterized_select, 'The SELECT query must use SQL placeholders and pass parameters separately to execute().'


def run_export(category, start_date, end_date, expected):
    result = subprocess.run(
        [sys.executable, EXPORT_PATH, category, start_date, end_date],
        cwd='/home/user', text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, f'export.py failed for valid arguments: {result.stderr}'
    assert read_json_output() == expected
    assert_database_pristine()


def test_export_accepts_exactly_three_arguments():
    invalid = [[], ['Electronics'], ['Electronics', '2023-01-01'], ['Electronics', '2023-01-01', '2023-12-31', 'extra']]
    for args in invalid:
        result = subprocess.run([sys.executable, EXPORT_PATH] + args, cwd='/home/user', stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert result.returncode != 0, f'export.py must reject invocation with {len(args)} arguments.'


def test_export_runs_for_varied_inputs_and_resists_injection():
    run_export('Electronics', '2023-05-14', '2023-05-14', [
        {'user_name': 'Alice Smith', 'email': 'alice@example.com', 'order_date': '2023-05-14', 'product_name': 'Headphones', 'quantity': 2},
        {'user_name': 'Alice Smith', 'email': 'alice@example.com', 'order_date': '2023-05-14', 'product_name': 'Laptop', 'quantity': 1},
    ])
    run_export('Books', '2022-01-01', '2022-12-31', [
        {'user_name': 'Alice Smith', 'email': 'alice@example.com', 'order_date': '2022-11-05', 'product_name': 'Novel', 'quantity': 5},
    ])
    run_export('Clothing', '2023-12-01', '2023-12-01', [
        {'user_name': 'Charlie Brown', 'email': 'charlie@example.com', 'order_date': '2023-12-01', 'product_name': 'T-Shirt', 'quantity': 3},
    ])
    run_export("Electronics' OR 1=1 --", '1900-01-01', '9999-12-31', [])
    run_export('No Such Category', '2023-01-01', '2023-12-31', [])
    run_export('Electronics', '2023-01-01', '2023-12-31', MANDATED_OUTPUT)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
