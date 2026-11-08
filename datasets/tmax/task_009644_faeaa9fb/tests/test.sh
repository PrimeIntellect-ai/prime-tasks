#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
import pytest

DB_PATH = '/home/user/logistics.db'
RUN_REPORT_PATH = '/home/user/run_report.sh'
INDEXES_SQL_PATH = '/home/user/indexes.sql'
OPTIMIZED_SQL_PATH = '/home/user/optimized.sql'
EXPECTED_KEYS = {
    'customer_id', 'customer_name', 'total_revenue',
    'latest_order_date', 'delayed_shipment_count'
}


def get_expected_results(limit, offset):
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    query = """
    WITH revenue AS (
        SELECT o.customer_id, SUM(oi.price) AS total_revenue
        FROM orders o
        JOIN order_items oi ON oi.order_id = o.id
        GROUP BY o.customer_id
    ), latest_orders AS (
        SELECT customer_id, MAX(order_date) AS latest_order_date
        FROM orders
        GROUP BY customer_id
    ), delayed_shipments AS (
        SELECT o.customer_id, COUNT(s.id) AS delayed_shipment_count
        FROM orders o
        JOIN shipments s ON s.order_id = o.id
        WHERE s.status = 'DELAYED'
        GROUP BY o.customer_id
    )
    SELECT c.id AS customer_id,
           c.name AS customer_name,
           r.total_revenue,
           lo.latest_order_date,
           ds.delayed_shipment_count
    FROM customers c
    JOIN revenue r ON r.customer_id = c.id
    JOIN latest_orders lo ON lo.customer_id = c.id
    JOIN delayed_shipments ds ON ds.customer_id = c.id
    WHERE ds.delayed_shipment_count > 0
    ORDER BY r.total_revenue DESC, c.id ASC
    LIMIT ? OFFSET ?
    """
    rows = [dict(row) for row in conn.execute(query, (limit, offset)).fetchall()]
    conn.close()
    for row in rows:
        row['total_revenue'] = round(row['total_revenue'], 2)
    return rows


def run_report(limit, offset):
    return subprocess.run(
        [RUN_REPORT_PATH, str(limit), str(offset)],
        capture_output=True, text=True, timeout=15
    )


def parse_report(result):
    assert result.returncode == 0, f"Script execution failed with error: {result.stderr}"
    try:
        output = json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Output is not valid JSON. Output was: {result.stdout[:200]}...")
    assert isinstance(output, list), 'Output should be a JSON array'
    return output


def assert_rows(output, expected):
    assert len(output) == len(expected), f"Expected {len(expected)} results, got {len(output)}"
    for i, (out_row, exp_row) in enumerate(zip(output, expected)):
        assert isinstance(out_row, dict), f"Row {i} is not a JSON object"
        assert set(out_row) == EXPECTED_KEYS, f"Row {i} has incorrect schema"
        assert int(out_row.get('customer_id', -1)) == exp_row['customer_id'], f"Row {i}: customer_id mismatch"
        assert out_row.get('customer_name') == exp_row['customer_name'], f"Row {i}: customer_name mismatch"
        assert round(float(out_row.get('total_revenue', 0)), 2) == exp_row['total_revenue'], f"Row {i}: total_revenue mismatch"
        assert out_row.get('latest_order_date') == exp_row['latest_order_date'], f"Row {i}: latest_order_date mismatch"
        assert int(out_row.get('delayed_shipment_count', -1)) == exp_row['delayed_shipment_count'], f"Row {i}: delayed_shipment_count mismatch"


def index_metadata(conn):
    result = {}
    for table in ('orders', 'order_items', 'shipments'):
        entries = []
        for row in conn.execute(f'PRAGMA index_list("{table}")'):
            name = row[1]
            quoted = name.replace('"', '""')
            columns = [r[2].lower() for r in conn.execute(f'PRAGMA index_info("{quoted}")') if r[2]]
            schema_row = conn.execute(
                "SELECT sql FROM sqlite_master WHERE type='index' AND name=?", (name,)
            ).fetchone()
            entries.append((columns, (schema_row[0] or '').lower() if schema_row else ''))
        result[table] = entries
    return result


def assert_required_indexes(metadata):
    assert any(cols and cols[0] == 'customer_id' for cols, _ in metadata['orders']), \
        'Missing an index on orders(customer_id) for the customer/order join'
    assert any(cols and cols[0] == 'order_id' for cols, _ in metadata['order_items']), \
        'Missing an index on order_items(order_id) for the order/item join'
    assert any(
        cols and cols[0] in ('order_id', 'status') and
        'order_id' in sql and 'status' in sql
        for cols, sql in metadata['shipments']
    ), 'Missing a shipments index that supports delayed-status filtering and the order join'


def test_files_exist():
    assert os.path.exists(INDEXES_SQL_PATH), f"Missing {INDEXES_SQL_PATH}"
    assert os.path.exists(OPTIMIZED_SQL_PATH), f"Missing {OPTIMIZED_SQL_PATH}"
    assert os.path.isfile(INDEXES_SQL_PATH), f"{INDEXES_SQL_PATH} is not a regular file"
    assert os.path.isfile(OPTIMIZED_SQL_PATH), f"{OPTIMIZED_SQL_PATH} is not a regular file"


def test_run_report_exists_and_executable():
    assert os.path.exists(RUN_REPORT_PATH), f"Missing {RUN_REPORT_PATH}"
    assert os.path.isfile(RUN_REPORT_PATH), f"{RUN_REPORT_PATH} is not a regular file"
    assert os.access(RUN_REPORT_PATH, os.X_OK), f"{RUN_REPORT_PATH} is not executable"


def test_indexes_created():
    conn = sqlite3.connect(DB_PATH)
    index_count = conn.execute(
        "SELECT count(*) FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
    ).fetchone()[0]
    assert index_count >= 1, 'No new indexes were created in the database.'
    assert_required_indexes(index_metadata(conn))
    conn.close()


def test_indexes_sql_contains_and_recreates_required_indexes():
    sql = open(INDEXES_SQL_PATH, encoding='utf-8').read()
    assert re.search(r'\bCREATE\s+(?:UNIQUE\s+)?INDEX\b', sql, re.I), \
        'indexes.sql does not contain CREATE INDEX statements'

    conn = sqlite3.connect(':memory:')
    conn.executescript("""
        CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT);
        CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, order_date TEXT);
        CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER, price REAL);
        CREATE TABLE shipments (id INTEGER PRIMARY KEY, order_id INTEGER, status TEXT,
                                actual_delivery TEXT, expected_delivery TEXT);
    """)
    try:
        conn.executescript(sql)
    except sqlite3.Error as exc:
        pytest.fail(f"indexes.sql cannot be applied to the stated schema: {exc}")
    assert_required_indexes(index_metadata(conn))
    conn.close()


def test_optimized_sql_is_executable_and_correct():
    sql = open(OPTIMIZED_SQL_PATH, encoding='utf-8').read()
    assert ':limit_val' in sql, 'optimized.sql is missing :limit_val'
    assert ':offset_val' in sql, 'optimized.sql is missing :offset_val'
    assert re.search(r'\bLIMIT\b[\s\S]{0,80}:limit_val', sql, re.I), \
        ':limit_val must be used by a LIMIT clause'
    assert re.search(r'\bOFFSET\b[\s\S]{0,80}:offset_val', sql, re.I), \
        ':offset_val must be used by an OFFSET clause'

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        actual = [dict(row) for row in conn.execute(
            sql, {'limit_val': 10000, 'offset_val': 0}
        ).fetchall()]
    except sqlite3.Error as exc:
        pytest.fail(f"optimized.sql is not directly executable with its named parameters: {exc}")
    finally:
        conn.close()
    assert_rows(actual, get_expected_results(10000, 0))


def test_run_report_output_format_and_correctness():
    limit, offset = 5, 0
    expected = get_expected_results(limit, offset)
    output = parse_report(run_report(limit, offset))
    assert_rows(output, expected)


def test_run_report_pagination():
    limit, offset = 3, 2
    expected = get_expected_results(limit, offset)
    output = parse_report(run_report(limit, offset))
    assert len(output) == len(expected), f"Pagination failed: Expected {len(expected)} results, got {len(output)}"
    if expected:
        assert int(output[0].get('customer_id', -1)) == expected[0]['customer_id'], \
            'Pagination returned incorrect starting record'
    assert_rows(output, expected)


@pytest.mark.parametrize('limit,offset', [
    (0, 0), (1, 0), (7, 1), (11, 9), (200, 0), (4, 200)
])
def test_additional_pagination_and_all_rows(limit, offset):
    assert_rows(parse_report(run_report(limit, offset)), get_expected_results(limit, offset))


def test_run_report_requires_exactly_two_arguments():
    for args in ([], ['5'], ['5', '0', 'extra']):
        result = subprocess.run(
            [RUN_REPORT_PATH] + args, capture_output=True, text=True, timeout=10
        )
        assert result.returncode != 0, f"run_report.sh accepted invalid argument list: {args}"


def test_run_report_reads_optimized_sql():
    original = open(OPTIMIZED_SQL_PATH, 'rb').read()
    sentinel = """SELECT 987654 AS customer_id,
       'sentinel' AS customer_name,
       12.34 AS total_revenue,
       '2099-12-31' AS latest_order_date,
       1 AS delayed_shipment_count
LIMIT :limit_val OFFSET :offset_val;
"""
    try:
        with open(OPTIMIZED_SQL_PATH, 'w', encoding='utf-8') as handle:
            handle.write(sentinel)
        output = parse_report(run_report(1, 0))
        assert output == [{
            'customer_id': 987654,
            'customer_name': 'sentinel',
            'total_revenue': 12.34,
            'latest_order_date': '2099-12-31',
            'delayed_shipment_count': 1
        }], 'run_report.sh did not execute the current contents of optimized.sql'
    finally:
        with open(OPTIMIZED_SQL_PATH, 'wb') as handle:
            handle.write(original)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
