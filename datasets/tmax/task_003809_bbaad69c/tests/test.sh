#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gc
import json
import os
import re
import runpy
import shutil
import sqlite3
import sys
import tempfile

SCRIPT_PATH = '/home/user/optimize_pipeline.py'
REPORT_PATH = '/home/user/top_customers_report.json'
DB_PATH = '/home/user/logistics.db'


def run_pipeline():
    assert os.path.exists(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"

    with open(SCRIPT_PATH, 'rb') as f:
        compile(f.read(), SCRIPT_PATH, 'exec')

    if os.path.lexists(REPORT_PATH):
        os.remove(REPORT_PATH)

    statements = []
    original_connect = sqlite3.connect
    original_dbapi_connect = sqlite3.dbapi2.connect

    def traced_connect(*args, **kwargs):
        conn = original_connect(*args, **kwargs)
        conn.set_trace_callback(statements.append)
        return conn

    sqlite3.connect = traced_connect
    sqlite3.dbapi2.connect = traced_connect
    old_argv = sys.argv
    old_cwd = os.getcwd()
    try:
        sys.argv = [SCRIPT_PATH]
        os.chdir('/home/user')
        try:
            runpy.run_path(SCRIPT_PATH, run_name='__main__')
        except SystemExit as exc:
            assert exc.code in (None, 0), f"Pipeline exited with status {exc.code}"
    finally:
        os.chdir(old_cwd)
        sys.argv = old_argv
        sqlite3.connect = original_connect
        sqlite3.dbapi2.connect = original_dbapi_connect
        gc.collect()

    assert os.path.exists(REPORT_PATH), f"Report file missing at {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file"
    with open(REPORT_PATH, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            raise AssertionError(f"File {REPORT_PATH} is not valid JSON: {exc}")
    return data, statements


def assert_original_report(data):
    assert isinstance(data, list), "Top level JSON structure must be a list"
    assert len(data) == 5, f"Expected exactly 5 customers in the report, found {len(data)}"

    ranks = [c.get('spend_rank') for c in data]
    assert ranks == sorted(ranks), "Customers are not sorted by spend_rank ascending"

    expected_spends = {
        2: {'name': 'Bob', 'segment': 'Enterprise', 'spend': 3500.0, 'rank': 1},
        1: {'name': 'Alice', 'segment': 'Retail', 'spend': 1000.0, 'rank': 2},
        6: {'name': 'Frank', 'segment': 'Enterprise', 'spend': 1000.0, 'rank': 2},
        4: {'name': 'Diana', 'segment': 'Enterprise', 'spend': 900.0, 'rank': 4},
        3: {'name': 'Charlie', 'segment': 'Retail', 'spend': 100.0, 'rank': 5},
    }
    expected_categories = {
        2: [('Electronics', 2500.0), ('Home', 1000.0)],
        1: [('Home', 1000.0)],
        6: [('Electronics', 1000.0)],
        4: [('Books', 500.0), ('Clothing', 400.0)],
        3: [('Books', 100.0)],
    }

    ids = [item.get('customer_id') for item in data]
    assert len(ids) == len(set(ids)), "Each customer_id must occur exactly once"
    assert set(ids) == set(expected_spends), "Report does not contain exactly the expected top 5 customers"

    for item in data:
        cid = item.get('customer_id')
        assert cid in expected_spends, f"Unexpected customer_id {cid} in report"
        expected = expected_spends[cid]
        assert item.get('customer_name') == expected['name'], f"Incorrect name for customer {cid}"
        assert item.get('segment') == expected['segment'], f"Incorrect segment for customer {cid}"
        assert float(item.get('lifetime_spend')) == expected['spend'], f"Incorrect lifetime_spend for customer {cid}"
        assert item.get('spend_rank') == expected['rank'], f"Incorrect spend_rank for customer {cid}"

        top_cats = item.get('top_categories', [])
        assert isinstance(top_cats, list), f"top_categories for customer {cid} must be a list"
        cat_spends = [c.get('category_spend') for c in top_cats]
        assert cat_spends == sorted(cat_spends, reverse=True), f"top_categories for customer {cid} not sorted by category_spend descending"

        exp_cats = expected_categories[cid]
        assert len(top_cats) == len(exp_cats), f"Incorrect number of categories for customer {cid}"
        for act_cat, exp_cat in zip(top_cats, exp_cats):
            assert act_cat.get('category_name') == exp_cat[0], f"Incorrect category_name for customer {cid}"
            assert float(act_cat.get('category_spend')) == exp_cat[1], f"Incorrect category_spend for customer {cid}"


def derive_expected():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        customers = conn.execute('''
            WITH totals AS (
                SELECT c.id AS customer_id, c.name AS customer_name, c.segment,
                       SUM(oi.quantity * oi.unit_price) AS lifetime_spend
                FROM customers c
                JOIN orders o ON o.customer_id = c.id
                JOIN order_items oi ON oi.order_id = o.id
                GROUP BY c.id, c.name, c.segment
            ), ranked AS (
                SELECT *, RANK() OVER (ORDER BY lifetime_spend DESC) AS spend_rank
                FROM totals
            )
            SELECT customer_id, customer_name, segment, lifetime_spend, spend_rank
            FROM ranked
            ORDER BY lifetime_spend DESC, customer_id ASC
            LIMIT 5
        ''').fetchall()

        result = []
        for customer in customers:
            cats = conn.execute('''
                SELECT cat.category_name,
                       SUM(oi.quantity * oi.unit_price) AS category_spend
                FROM orders o
                JOIN order_items oi ON oi.order_id = o.id
                JOIN products p ON p.id = oi.product_id
                JOIN categories cat ON cat.id = p.category_id
                WHERE o.customer_id = ?
                GROUP BY cat.id, cat.category_name
                ORDER BY category_spend DESC, cat.category_name ASC
                LIMIT 3
            ''', (customer['customer_id'],)).fetchall()
            result.append({
                'customer_id': customer['customer_id'],
                'customer_name': customer['customer_name'],
                'segment': customer['segment'],
                'lifetime_spend': round(customer['lifetime_spend'], 2),
                'spend_rank': customer['spend_rank'],
                'top_categories': [
                    (row['category_name'], round(row['category_spend'], 2)) for row in cats
                ],
            })
        return result
    finally:
        conn.close()


def assert_dynamic_report(data, expected):
    assert isinstance(data, list), "Top level JSON structure must be a list"
    assert len(data) == 5, f"Expected exactly 5 customers, found {len(data)}"
    assert [x.get('spend_rank') for x in data] == sorted(x.get('spend_rank') for x in data), \
        "Customers are not sorted by spend_rank ascending"

    expected_by_id = {x['customer_id']: x for x in expected}
    ids = [x.get('customer_id') for x in data]
    assert len(ids) == len(set(ids)), "Each customer_id must occur exactly once"
    assert set(ids) == set(expected_by_id), "Report does not completely cover the derived top 5 customers"

    for item in data:
        exp = expected_by_id[item.get('customer_id')]
        cid = exp['customer_id']
        assert item.get('customer_name') == exp['customer_name'], f"Incorrect name for customer {cid}"
        assert item.get('segment') == exp['segment'], f"Incorrect segment for customer {cid}"
        assert round(float(item.get('lifetime_spend')), 2) == exp['lifetime_spend'], f"Incorrect lifetime_spend for customer {cid}"
        assert item.get('spend_rank') == exp['spend_rank'], f"Incorrect spend_rank for customer {cid}"

        cats = item.get('top_categories')
        assert isinstance(cats, list), f"top_categories for customer {cid} must be a list"
        spends = [float(x.get('category_spend')) for x in cats]
        assert spends == sorted(spends, reverse=True), f"top_categories for customer {cid} are not sorted descending"
        actual_cats = [(x.get('category_name'), round(float(x.get('category_spend')), 2)) for x in cats]
        assert actual_cats == exp['top_categories'], f"Incorrect top_categories for customer {cid}"


def assert_required_sql(statements):
    sql = '\n'.join(statements)
    sql = re.sub(r'/\*.*?\*/', ' ', sql, flags=re.S)
    sql = re.sub(r'--[^\n]*', ' ', sql)
    assert re.search(r'\bWITH\b', sql, re.I), "The executed SQL did not use a CTE"
    assert re.search(r'\bJOIN\b', sql, re.I), "The executed SQL did not use a JOIN"
    assert re.search(r'\bRANK\s*\(\s*\)\s*OVER\s*\(', sql, re.I), \
        "The executed SQL did not calculate spend rank with a SQL window function"


def main():
    original_data, original_sql = run_pipeline()
    assert_original_report(original_data)

    fd, backup_path = tempfile.mkstemp(prefix='logistics-', suffix='.db')
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)
    try:
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute("UPDATE customers SET name = name || ' Updated', segment = 'Segment-' || id")
            conn.execute("UPDATE categories SET category_name = 'Garden' WHERE id = 4")
            next_order = conn.execute('SELECT COALESCE(MAX(id), 0) + 1 FROM orders').fetchone()[0]
            next_item = conn.execute('SELECT COALESCE(MAX(id), 0) + 1 FROM order_items').fetchone()[0]
            product_ids = [1, 3, 5, 7]
            multipliers = [400.13, 300.17, 200.19, 100.23]
            for cid in range(1, 7):
                oid = next_order
                next_order += 1
                conn.execute('INSERT INTO orders(id, customer_id, order_date) VALUES (?, ?, ?)',
                             (oid, cid, '2024-02-01'))
                for product_id, multiplier in zip(product_ids, multipliers):
                    conn.execute('''
                        INSERT INTO order_items(id, order_id, product_id, quantity, unit_price)
                        VALUES (?, ?, ?, 1, ?)
                    ''', (next_item, oid, product_id, cid * multiplier))
                    next_item += 1
            conn.commit()
        finally:
            conn.close()

        expected = derive_expected()
        dynamic_data, dynamic_sql = run_pipeline()
        assert_dynamic_report(dynamic_data, expected)
        assert_required_sql(original_sql + dynamic_sql)
    finally:
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)


if __name__ == '__main__':
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
