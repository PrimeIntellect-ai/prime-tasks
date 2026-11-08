#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import sys
import sqlite3
import gzip
import json
import secrets
import subprocess
import pytest

DB_PATH = '/home/user/ecommerce.db'
REPORT_PATH = '/home/user/cohort_report.jsonl.gz'
SCRIPT_PATH = '/home/user/optimize_and_export.py'


def build_pristine_database():
    for path in (DB_PATH, DB_PATH + '-wal', DB_PATH + '-shm'):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    token = secrets.token_hex(4)
    price_offset = secrets.randbelow(20)
    amount_offset = secrets.randbelow(5000) / 100.0

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.executescript('''
        CREATE TABLE customers (id INTEGER PRIMARY KEY, joined_date TEXT, country TEXT);
        CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, order_date TEXT, total_amount REAL);
        CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER, product_id INTEGER, quantity INTEGER, price REAL);
        CREATE TABLE products (id INTEGER PRIMARY KEY, category TEXT, name TEXT);
    ''')

    c.executemany('INSERT INTO customers VALUES (?, ?, ?)', [
        (1, '2023-01-04', 'US'),
        (2, '2023-01-27', 'UK'),
        (3, '2023-02-11', 'CA'),
        (4, '2023-03-19', 'AU'),
    ])
    c.executemany('INSERT INTO orders VALUES (?, ?, ?, ?)', [
        (101, 1, '2023-01-05', round(123.45 + amount_offset, 2)),
        (102, 2, '2023-02-02', round(287.10 + amount_offset, 2)),
        (103, 3, '2023-02-12', round(511.25 + amount_offset, 2)),
        (104, 4, '2023-04-01', round(98.75 + amount_offset, 2)),
        (105, 1, '2023-05-09', round(201.30 + amount_offset, 2)),
    ])
    c.executemany('INSERT INTO products VALUES (?, ?, ?)', [
        (10, 'Electronics-' + token, 'Device'),
        (11, 'Apparel-' + token, 'Jacket'),
        (12, 'Books-' + token, 'Reference'),
        (13, 'Garden-' + token, 'Tool'),
    ])

    p10 = 101.0 + price_offset
    p11 = 67.0 + price_offset
    p12 = 23.0 + price_offset
    p13 = 41.0 + price_offset
    c.executemany('INSERT INTO order_items VALUES (?, ?, ?, ?, ?)', [
        (1001, 101, 10, 2, p10),
        (1002, 101, 11, 1, p11),
        (1003, 102, 10, 1, p10),
        (1004, 102, 12, 5, p12),
        (1005, 105, 11, 4, p11),
        (1006, 103, 12, 3, p12),
        (1007, 103, 13, 4, p13),
        (1008, 104, 10, 1, p10),
        (1009, 104, 11, 2, p11),
    ])
    conn.commit()
    conn.close()


def calculate_expected(db_path):
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute('''
        SELECT strftime('%Y-%m', c.joined_date) AS cohort, SUM(o.total_amount)
        FROM customers c
        JOIN orders o ON c.id = o.customer_id
        GROUP BY cohort
        ORDER BY cohort
    ''')
    expected_clv = {row[0]: round(row[1], 2) for row in c.fetchall()}

    c.execute('''
        SELECT strftime('%Y-%m', c.joined_date) AS cohort, p.category,
               SUM(oi.quantity * oi.price) AS revenue
        FROM customers c
        JOIN orders o ON c.id = o.customer_id
        JOIN order_items oi ON o.id = oi.order_id
        JOIN products p ON oi.product_id = p.id
        GROUP BY cohort, p.category
    ''')
    cohort_categories = {}
    for cohort, category, revenue in c.fetchall():
        cohort_categories.setdefault(cohort, []).append({
            'category': category,
            'revenue': round(revenue, 2),
        })

    expected = []
    for cohort in sorted(expected_clv):
        categories = sorted(
            cohort_categories.get(cohort, []),
            key=lambda item: item['revenue'],
            reverse=True,
        )[:2]
        expected.append({
            'cohort': cohort,
            'total_clv': expected_clv[cohort],
            'top_categories': categories,
        })
    conn.close()
    return expected


build_pristine_database()
TRUSTED_EXPECTED = calculate_expected(DB_PATH)
assert TRUSTED_EXPECTED, 'Internal test fixture unexpectedly produced no cohorts.'
RUN_RESULT = None


@pytest.fixture(scope='session', autouse=True)
def execute_submission():
    global RUN_RESULT
    assert os.path.exists(SCRIPT_PATH), f'Script {SCRIPT_PATH} does not exist.'
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f'{SCRIPT_PATH} must be a regular file.'

    try:
        os.remove(REPORT_PATH)
    except FileNotFoundError:
        pass

    try:
        RUN_RESULT = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f'{SCRIPT_PATH} did not finish within 30 seconds.')

    assert RUN_RESULT.returncode == 0, (
        f'{SCRIPT_PATH} exited with status {RUN_RESULT.returncode}.\n'
        f'stdout:\n{RUN_RESULT.stdout}\n'
        f'stderr:\n{RUN_RESULT.stderr}'
    )
    yield


def test_script_exists_and_runs():
    assert RUN_RESULT is not None, 'The submission script was not executed.'
    assert RUN_RESULT.returncode == 0


def test_indexes_created():
    """Verify that the student created indexes on foreign keys and date columns."""
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    c.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%';")
    indexes = c.fetchall()
    conn.close()

    assert len(indexes) > 0, "No custom indexes were created in the database."

    # We expect indexes on foreign keys and/or date columns.
    # Just checking that at least one index exists on the relevant tables.
    indexed_tables = {row[1] for row in indexes}
    expected_tables_to_index = {'orders', 'order_items', 'customers'}
    assert len(indexed_tables.intersection(expected_tables_to_index)) > 0, \
        "Indexes should be created on tables involved in joins or date filtering (orders, order_items, customers)."


def test_report_exists_and_is_gzipped():
    """Verify the report file exists and is a valid gzip file."""
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    try:
        with gzip.open(REPORT_PATH, 'rt') as f:
            f.read(1)
    except Exception as e:
        pytest.fail(f"{REPORT_PATH} is not a valid gzip file: {e}")


def test_report_contents():
    """Verify the contents of the report match the database truth."""
    # Compute the expected results from the database
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # Calculate expected total_clv per cohort
    c.execute("""
        SELECT strftime('%Y-%m', c.joined_date) AS cohort, SUM(o.total_amount)
        FROM customers c
        JOIN orders o ON c.id = o.customer_id
        GROUP BY cohort
        ORDER BY cohort
    """)
    expected_clv = {row[0]: round(row[1], 2) for row in c.fetchall()}

    # Calculate expected top categories per cohort
    c.execute("""
        SELECT strftime('%Y-%m', c.joined_date) AS cohort, p.category, SUM(oi.quantity * oi.price) as revenue
        FROM customers c
        JOIN orders o ON c.id = o.customer_id
        JOIN order_items oi ON o.id = oi.order_id
        JOIN products p ON oi.product_id = p.id
        GROUP BY cohort, p.category
    """)

    cohort_categories = {}
    for row in c.fetchall():
        cohort, category, revenue = row
        if cohort not in cohort_categories:
            cohort_categories[cohort] = []
        cohort_categories[cohort].append({"category": category, "revenue": round(revenue, 2)})

    expected_cohorts = []
    for cohort in sorted(expected_clv.keys()):
        # Sort categories by revenue descending, then take top 2
        sorted_cats = sorted(cohort_categories.get(cohort, []), key=lambda x: x['revenue'], reverse=True)[:2]
        expected_cohorts.append({
            "cohort": cohort,
            "total_clv": expected_clv[cohort],
            "top_categories": sorted_cats
        })
    conn.close()

    # Read the actual results
    actual_cohorts = []
    with gzip.open(REPORT_PATH, 'rt') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                actual_cohorts.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {REPORT_PATH} is not valid JSON.")

    # Verify the structure and contents
    assert len(actual_cohorts) == len(expected_cohorts), \
        f"Expected {len(expected_cohorts)} cohorts, but found {len(actual_cohorts)}."

    for i, (actual, expected) in enumerate(zip(actual_cohorts, expected_cohorts)):
        assert actual.get("cohort") == expected["cohort"], \
            f"Row {i}: Expected cohort '{expected['cohort']}', got '{actual.get('cohort')}'."

        assert "total_clv" in actual, f"Row {i}: Missing 'total_clv'."
        assert round(actual["total_clv"], 2) == expected["total_clv"], \
            f"Row {i}: Expected total_clv {expected['total_clv']}, got {actual['total_clv']}."

        assert "top_categories" in actual, f"Row {i}: Missing 'top_categories'."
        actual_cats = actual["top_categories"]
        expected_cats = expected["top_categories"]

        assert len(actual_cats) == len(expected_cats), \
            f"Row {i}: Expected {len(expected_cats)} top categories, got {len(actual_cats)}."

        for j, (a_cat, e_cat) in enumerate(zip(actual_cats, expected_cats)):
            assert a_cat.get("category") == e_cat["category"], \
                f"Row {i}, Category {j}: Expected '{e_cat['category']}', got '{a_cat.get('category')}'."
            assert round(a_cat.get("revenue", 0), 2) == e_cat["revenue"], \
                f"Row {i}, Category {j}: Expected revenue {e_cat['revenue']}, got {a_cat.get('revenue')}."


def test_report_matches_pristine_fixture():
    """Reject reports made valid only by deleting or replacing source rows."""
    actual = []
    with gzip.open(REPORT_PATH, 'rt') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                actual.append(json.loads(line))
            except json.JSONDecodeError as exc:
                pytest.fail(f'Line {line_num} in {REPORT_PATH} is not valid JSON: {exc}')

    assert actual == TRUSTED_EXPECTED, (
        'The report does not match the non-empty pristine database fixture that '
        'was installed before the submission script ran.'
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
