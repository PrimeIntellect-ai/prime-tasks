#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import shutil
import sqlite3
import subprocess
import tempfile
import uuid
import pytest

SCRIPT_PATH = '/home/user/generate_report.py'
REPORT_PATH = '/home/user/report.json'
DB_PATH = '/home/user/company.db'


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"


def test_report_json_exists_and_correct():
    assert os.path.exists(REPORT_PATH), f"Report not found at {REPORT_PATH}"

    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON.")

    expected_data = [
        {"region": "North", "revenue": 2100.0},
        {"region": "South", "revenue": 2000.0},
        {"region": "East", "revenue": 900.0},
        {"region": "West", "revenue": 50.0}
    ]

    assert isinstance(data, list), f"Expected a JSON array, got {type(data).__name__}"
    assert data == expected_data, f"Report data for 'Electronics' does not match expected output or is not sorted correctly. Got: {data}"


def test_script_functionality_with_different_category():
    result = subprocess.run(
        ['python3', SCRIPT_PATH, 'Furniture'],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"Script failed when running with 'Furniture' category. Stderr: {result.stderr}"
    assert os.path.exists(REPORT_PATH), f"Report not found at {REPORT_PATH} after running script."

    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON after running with 'Furniture'.")

    expected_data = [
        {"region": "North", "revenue": 200.0}
    ]

    assert data == expected_data, f"Report data for 'Furniture' does not match expected output. Got: {data}"


def test_source_uses_parameterized_execute_and_joins():
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()

    tree = ast.parse(source, filename=SCRIPT_PATH)
    parameterized_executes = [
        node for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == 'execute'
        and len(node.args) >= 2
    ]
    assert parameterized_executes, "SQLite execute() must receive query parameters separately from the SQL string."
    assert source.upper().count('JOIN') >= 3, "The report query must join customers, orders, order_items, and products."


def test_script_uses_database_for_unpredictable_category():
    backup_fd, backup_path = tempfile.mkstemp(prefix='company-db-backup-', suffix='.db')
    os.close(backup_fd)
    shutil.copy2(DB_PATH, backup_path)

    category = "Audit'" + uuid.uuid4().hex
    suffix = uuid.uuid4().hex[:10]
    regions = [f'Zulu-{suffix}', f'Alpha-{suffix}', f'Middle-{suffix}']

    try:
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()

        def next_id(table):
            return cur.execute(f'SELECT COALESCE(MAX(id), 0) + 1 FROM {table}').fetchone()[0]

        customer_id = next_id('customers')
        product_id = next_id('products')
        order_id = next_id('orders')
        item_id = next_id('order_items')

        cur.executemany('INSERT INTO customers(id, name, region) VALUES (?, ?, ?)', [
            (customer_id, 'Audit Customer 1', regions[0]),
            (customer_id + 1, 'Audit Customer 2', regions[1]),
            (customer_id + 2, 'Audit Customer 3', regions[2]),
        ])
        cur.executemany('INSERT INTO products(id, name, category) VALUES (?, ?, ?)', [
            (product_id, 'Audit Product', category),
            (product_id + 1, 'Irrelevant Product', category + '-other'),
        ])
        cur.executemany('INSERT INTO orders(id, customer_id, order_date) VALUES (?, ?, ?)', [
            (order_id, customer_id, '2026-01-01'),
            (order_id + 1, customer_id + 1, '2026-01-02'),
            (order_id + 2, customer_id + 2, '2026-01-03'),
            (order_id + 3, customer_id + 2, '2026-01-04'),
        ])
        cur.executemany('INSERT INTO order_items(id, order_id, product_id, quantity, price) VALUES (?, ?, ?, ?, ?)', [
            (item_id, order_id, product_id, 2, 12.5),
            (item_id + 1, order_id + 1, product_id, 1, 25.0),
            (item_id + 2, order_id + 2, product_id, 3, 10.0),
            (item_id + 3, order_id + 3, product_id + 1, 50, 999.0),
        ])
        conn.commit()

        rows = cur.execute('''
            SELECT c.region, SUM(oi.quantity * oi.price) AS revenue
            FROM customers AS c
            JOIN orders AS o ON o.customer_id = c.id
            JOIN order_items AS oi ON oi.order_id = o.id
            JOIN products AS p ON p.id = oi.product_id
            WHERE p.category = ?
            GROUP BY c.region
            ORDER BY revenue DESC, c.region ASC
        ''', (category,)).fetchall()
        expected = [{"region": region, "revenue": float(revenue)} for region, revenue in rows]
        conn.close()

        result = subprocess.run(
            ['python3', SCRIPT_PATH, category],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"Script failed for a generated category. Stderr: {result.stderr}"
        assert os.path.isfile(REPORT_PATH), f"Report not found at {REPORT_PATH} after running script."

        with open(REPORT_PATH, 'r') as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"File {REPORT_PATH} does not contain valid JSON for the generated category.")

        assert data == expected, f"Report was not derived correctly from the database. Expected {expected}, got {data}"
        assert all(isinstance(item.get('revenue'), float) for item in data), "Every revenue value must be a float."
    finally:
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
