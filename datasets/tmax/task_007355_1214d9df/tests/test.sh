#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
import subprocess
from collections import Counter, defaultdict

import pytest

RAW_DATA_PATH = '/home/user/raw_data/orders.json'
DB_PATH = '/home/user/ecommerce.db'
SUMMARY_PATH = '/home/user/summary.json'
ETL_PATH = '/home/user/etl.py'
REPORT_PATH = '/home/user/report.py'

EXPECTED_TABLES = {'users', 'products', 'orders', 'order_items'}
EXPECTED_SCHEMAS = {
    'users': [
        ('user_id', 'TEXT', 1),
        ('name', 'TEXT', 0),
        ('email', 'TEXT', 0),
    ],
    'products': [
        ('product_id', 'TEXT', 1),
        ('name', 'TEXT', 0),
        ('category', 'TEXT', 0),
        ('price', 'REAL', 0),
    ],
    'orders': [
        ('order_id', 'TEXT', 1),
        ('user_id', 'TEXT', 0),
        ('order_date', 'TEXT', 0),
    ],
    'order_items': [
        ('order_id', 'TEXT', 0),
        ('product_id', 'TEXT', 0),
        ('quantity', 'INTEGER', 0),
    ],
}

# Canonical rows from the task input. These prevent changing the input and then
# satisfying checks with a different, easier dataset.
CANONICAL_USERS = {
    ('U101', 'Alice Smith', 'alice@example.com'),
    ('U102', 'Bob Jones', 'bob@example.com'),
    ('U103', 'Charlie Brown', 'charlie@example.com'),
}
CANONICAL_PRODUCTS = {
    ('P001', 'Laptop', 'Electronics', 1000.0),
    ('P002', 'Mouse', 'Electronics', 50.0),
    ('P003', 'Desk Chair', 'Furniture', 150.0),
    ('P004', 'Headphones', 'Electronics', 200.0),
    ('P005', 'Coffee Table', 'Furniture', 300.0),
}
CANONICAL_ORDERS = {
    ('O001', 'U101', '2023-10-01T10:00:00Z'),
    ('O002', 'U102', '2023-10-02T11:30:00Z'),
    ('O003', 'U103', '2023-10-03T09:15:00Z'),
}
CANONICAL_ORDER_ITEMS = Counter({
    ('O001', 'P001', 1): 1,
    ('O001', 'P002', 2): 1,
    ('O002', 'P003', 2): 1,
    ('O002', 'P001', 1): 1,
    ('O003', 'P004', 3): 1,
    ('O003', 'P005', 1): 1,
})


def run_script(path):
    result = subprocess.run(
        ['python3', path], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        f'{path} failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def get_expected_data():
    if not os.path.isfile(RAW_DATA_PATH):
        pytest.fail(f"Raw data file {RAW_DATA_PATH} is missing.")

    with open(RAW_DATA_PATH, 'r') as f:
        orders = json.load(f)

    users = {}
    products = {}
    order_records = {}
    order_items = []
    category_user_spent = defaultdict(lambda: defaultdict(float))

    for order in orders:
        o_id = order['order_id']
        u = order['user']
        u_id = u['user_id']

        users[u_id] = u
        order_records[o_id] = {
            'order_id': o_id,
            'user_id': u_id,
            'order_date': order['order_date']
        }

        for item in order['items']:
            p = item['product']
            p_id = p['product_id']
            qty = item['quantity']
            products[p_id] = p
            order_items.append({
                'order_id': o_id,
                'product_id': p_id,
                'quantity': qty
            })
            category_user_spent[p['category']][u['name']] += p['price'] * qty

    expected_summary = []
    for category, user_spent in category_user_spent.items():
        sorted_users = sorted(user_spent.items(), key=lambda x: (-x[1], x[0]))
        top_user_name, top_spent = sorted_users[0]
        expected_summary.append({
            'category': category,
            'top_user_name': top_user_name,
            'total_spent_by_top_user': round(top_spent, 2)
        })

    expected_summary.sort(key=lambda x: x['category'])
    return users, products, order_records, order_items, expected_summary


def read_summary():
    assert os.path.isfile(SUMMARY_PATH), f"Summary file {SUMMARY_PATH} is missing. The report script did not create it."
    with open(SUMMARY_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{SUMMARY_PATH} is not valid JSON.")


def summary_from_database():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute('''
            SELECT p.category, u.name, SUM(p.price * oi.quantity)
            FROM order_items AS oi
            JOIN orders AS o ON o.order_id = oi.order_id
            JOIN users AS u ON u.user_id = o.user_id
            JOIN products AS p ON p.product_id = oi.product_id
            GROUP BY p.category, u.user_id, u.name
        ''').fetchall()
    finally:
        conn.close()

    by_category = defaultdict(list)
    for category, name, spent in rows:
        by_category[category].append((float(spent), name))

    result = []
    for category in sorted(by_category):
        spent, name = sorted(by_category[category], key=lambda x: (-x[0], x[1]))[0]
        result.append({
            'category': category,
            'top_user_name': name,
            'total_spent_by_top_user': round(spent, 2),
        })
    return result


def test_scripts_exist_and_run():
    assert os.path.isfile(ETL_PATH), f"ETL script {ETL_PATH} is missing."
    assert os.path.isfile(REPORT_PATH), f"Report script {REPORT_PATH} is missing."

    for path in (DB_PATH, SUMMARY_PATH):
        if os.path.exists(path):
            os.remove(path)

    run_script(ETL_PATH)
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing. The ETL script did not create it."
    run_script(REPORT_PATH)


def test_db_exists():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing. The ETL script did not create it."


def test_db_tables_and_counts():
    users, products, order_records, order_items, _ = get_expected_data()
    conn = None
    try:
        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()

        c.execute("SELECT count(*) FROM users")
        assert c.fetchone()[0] == len(users), "Incorrect number of rows in 'users' table. Did you deduplicate properly?"

        c.execute("SELECT count(*) FROM products")
        assert c.fetchone()[0] == len(products), "Incorrect number of rows in 'products' table. Did you deduplicate properly?"

        c.execute("SELECT count(*) FROM orders")
        assert c.fetchone()[0] == len(order_records), "Incorrect number of rows in 'orders' table."

        c.execute("SELECT count(*) FROM order_items")
        assert c.fetchone()[0] == len(order_items), "Incorrect number of rows in 'order_items' table."

        actual_tables = {
            row[0] for row in c.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
            )
        }
        assert actual_tables == EXPECTED_TABLES, f'Expected exactly tables {sorted(EXPECTED_TABLES)}, got {sorted(actual_tables)}.'

        for table, expected_schema in EXPECTED_SCHEMAS.items():
            info = c.execute(f'PRAGMA table_info({table})').fetchall()
            actual_schema = [(row[1], row[2].upper(), row[5]) for row in info]
            assert actual_schema == expected_schema, (
                f"Incorrect schema for '{table}'. Expected {expected_schema}, got {actual_schema}."
            )

        assert set(c.execute('SELECT user_id, name, email FROM users')) == CANONICAL_USERS, "The users table does not contain the required relational data."
        assert set(c.execute('SELECT product_id, name, category, price FROM products')) == CANONICAL_PRODUCTS, "The products table does not contain the required relational data."
        assert set(c.execute('SELECT order_id, user_id, order_date FROM orders')) == CANONICAL_ORDERS, "The orders table does not contain the required relational data."
        assert Counter(c.execute('SELECT order_id, product_id, quantity FROM order_items')) == CANONICAL_ORDER_ITEMS, "The order_items table does not contain the required relational data."

    except sqlite3.OperationalError as e:
        pytest.fail(f"SQLite OperationalError: {e}. Ensure all required tables are created with the correct schemas.")
    finally:
        if conn is not None:
            conn.close()


def test_report_uses_database_and_restore_outputs():
    # Change relational data after ETL and require report.py to reflect it. This
    # rejects reports generated directly from orders.json instead of the database.
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("UPDATE products SET category = 'ZZ Dynamic', price = 7.25 WHERE product_id = 'P001'")
        conn.commit()
    finally:
        conn.close()

    try:
        if os.path.exists(SUMMARY_PATH):
            os.remove(SUMMARY_PATH)
        run_script(REPORT_PATH)
        assert read_summary() == summary_from_database(), 'report.py did not calculate its report from the SQLite relational data.'
    finally:
        for path in (DB_PATH, SUMMARY_PATH):
            if os.path.exists(path):
                os.remove(path)
        run_script(ETL_PATH)
        run_script(REPORT_PATH)


def test_summary_json():
    assert os.path.isfile(SUMMARY_PATH), f"Summary file {SUMMARY_PATH} is missing. The report script did not create it."
    _, _, _, _, expected_summary = get_expected_data()
    actual_summary = read_summary()

    assert isinstance(actual_summary, list), "summary.json must contain a JSON array at the root level."
    assert len(actual_summary) == len(expected_summary), f"Expected {len(expected_summary)} categories in summary.json, but got {len(actual_summary)}."

    for i in range(len(expected_summary)):
        expected = expected_summary[i]
        actual = actual_summary[i]

        assert isinstance(actual, dict), f'Entry {i} in summary.json must be an object.'
        assert set(actual) == {'category', 'top_user_name', 'total_spent_by_top_user'}, f'Entry {i} has an incorrect JSON structure.'
        assert actual.get("category") == expected["category"], f"Expected category '{expected['category']}' at index {i}. Ensure the array is sorted alphabetically by category."
        assert actual.get("top_user_name") == expected["top_user_name"], f"Expected top_user_name '{expected['top_user_name']}' for category '{expected['category']}'. Check your tie-breaking logic."
        assert isinstance(actual.get("total_spent_by_top_user"), float), f"total_spent_by_top_user for '{expected['category']}' must be a float."
        assert round(actual.get("total_spent_by_top_user"), 2) == expected["total_spent_by_top_user"], f"Expected total_spent_by_top_user {expected['total_spent_by_top_user']} for category '{expected['category']}'."
        assert actual.get("total_spent_by_top_user") == round(actual.get("total_spent_by_top_user"), 2), f"total_spent_by_top_user for '{expected['category']}' must be rounded to 2 decimal places."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
