#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import math
import os
import signal
import sqlite3
import subprocess
import sys
import time
import uuid
import multiprocessing

import pytest

DB_PATH = '/home/user/analytics.db'
API_PATH = '/home/user/query_api.py'
CSV_PATH = '/home/user/raw_data/orders.csv'
BENCHMARK_PATH = '/home/user/benchmark.py'
METRIC_PATH = '/home/user/execution_time.txt'
PERF_CASES = []
PERF_ID_DATES = {}


def load_api():
    sys.path.insert(0, '/home/user')
    import query_api
    return query_api


def assert_summary(actual, expected):
    assert isinstance(actual, dict), f'Expected dict, got {type(actual).__name__}'
    assert {'total_orders', 'total_spent', 'recent_orders'} <= set(actual)
    assert actual['total_orders'] == expected['total_orders']
    assert float(actual['total_spent']) == pytest.approx(expected['total_spent'], abs=1e-7)
    assert actual['recent_orders'] == expected['recent_orders']


def expected_summary(customer_id, page, page_size):
    conn = sqlite3.connect(DB_PATH)
    total_orders, total_spent = conn.execute(
        'SELECT COUNT(*), COALESCE(SUM(amount), 0) FROM orders WHERE customer_id = ?',
        (customer_id,),
    ).fetchone()
    rows = conn.execute(
        'SELECT order_id FROM orders WHERE customer_id = ? '
        'ORDER BY order_date DESC LIMIT ? OFFSET ?',
        (customer_id, page_size, (page - 1) * page_size),
    ).fetchall()
    conn.close()
    return {
        'total_orders': total_orders,
        'total_spent': float(total_spent or 0),
        'recent_orders': [row[0] for row in rows],
    }


def worker(worker_number):
    try:
        api = load_api()
        for i in range(500):
            customer_id, page, page_size, total, spent, expected_dates = PERF_CASES[(i + worker_number) % len(PERF_CASES)]
            result = api.get_customer_summary(DB_PATH, customer_id, page, page_size)
            if not isinstance(result, dict):
                raise AssertionError('API did not return a dictionary')
            if result.get('total_orders') != total:
                raise AssertionError('Incorrect total_orders')
            if not math.isclose(float(result.get('total_spent')), spent, rel_tol=1e-9, abs_tol=1e-7):
                raise AssertionError('Incorrect total_spent')
            recent = result.get('recent_orders')
            if not isinstance(recent, list) or len(recent) != len(expected_dates):
                raise AssertionError('Incorrect recent_orders length')
            try:
                actual_dates = [PERF_ID_DATES[order_id] for order_id in recent]
            except KeyError as exc:
                raise AssertionError(f'Order from wrong customer: {exc}')
            if actual_dates != sorted(actual_dates, reverse=True):
                raise AssertionError('recent_orders is not sorted by date descending')
            if sorted(actual_dates, reverse=True) != expected_dates:
                raise AssertionError('Incorrect pagination results')
    except BaseException:
        import traceback
        traceback.print_exc()
        raise


def test_database_and_api_exist():
    assert os.path.isfile(DB_PATH), 'Database /home/user/analytics.db not found.'
    assert os.path.isfile(API_PATH), 'API module /home/user/query_api.py not found.'


def test_csv_was_loaded_and_schema_is_correct():
    expected = {}
    with open(CSV_PATH, newline='') as handle:
        reader = csv.DictReader(handle)
        assert reader.fieldnames == ['order_id', 'customer_id', 'amount', 'order_date']
        for row in reader:
            expected[row['order_id']] = (
                row['customer_id'], float(row['amount']), row['order_date']
            )
    assert expected, 'Source CSV is empty.'

    conn = sqlite3.connect(DB_PATH)
    columns = {row[1]: (row[2] or '').upper() for row in conn.execute('PRAGMA table_info(orders)')}
    assert columns.get('order_id') == 'TEXT'
    assert columns.get('customer_id') == 'TEXT'
    assert columns.get('amount') == 'REAL'
    assert columns.get('order_date') == 'TEXT'

    seen = set()
    for order_id, customer_id, amount, order_date in conn.execute(
        'SELECT order_id, customer_id, amount, order_date FROM orders'
    ):
        if order_id not in expected:
            continue
        assert order_id not in seen, f'Duplicate source order_id {order_id}'
        exp_customer, exp_amount, exp_date = expected[order_id]
        assert customer_id == exp_customer
        assert float(amount) == pytest.approx(exp_amount, abs=1e-9)
        assert order_date == exp_date
        seen.add(order_id)
    conn.close()
    assert len(seen) == len(expected), f'Only {len(seen)} of {len(expected)} CSV rows were loaded.'


def test_pragmas_and_indexes():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute('PRAGMA journal_mode;')
    journal_mode = cursor.fetchone()[0].upper()
    assert journal_mode == 'WAL', f'Expected journal_mode WAL, got {journal_mode}'

    cursor.execute('PRAGMA synchronous;')
    synchronous = cursor.fetchone()[0]
    assert str(synchronous) in ('1', 'NORMAL'), f'Expected synchronous NORMAL (1), got {synchronous}'

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index';")
    indexes = [row[0] for row in cursor.fetchall() if row[0] is not None]
    assert 'idx_cust_date' in indexes, "Index 'idx_cust_date' is missing."
    assert 'idx_cust_amount' in indexes, "Index 'idx_cust_amount' is missing."

    def index_definition(name):
        rows = conn.execute(f'PRAGMA index_xinfo({name!r})').fetchall()
        return [(row[2], row[3]) for row in rows if row[5] == 1 and row[1] >= 0]

    assert index_definition('idx_cust_date') == [('customer_id', 0), ('order_date', 1)], \
        'idx_cust_date must be exactly (customer_id, order_date DESC).'
    assert index_definition('idx_cust_amount') == [('customer_id', 0), ('amount', 0)], \
        'idx_cust_amount must be exactly (customer_id, amount).'
    conn.close()


def test_api_aggregation_filtering_sorting_pagination_and_parameters():
    api = load_api()

    marker = uuid.uuid4().hex
    normal_customer = 'VERIFY_' + marker
    injection_customer = "' OR 1=1 -- " + marker
    rows = [
        ('V_' + marker + '_1', normal_customer, 10.25, '2040-01-01 01:00:00'),
        ('V_' + marker + '_2', normal_customer, 20.50, '2040-01-03 01:00:00'),
        ('V_' + marker + '_3', normal_customer, 30.75, '2040-01-02 01:00:00'),
        ('V_' + marker + '_4', normal_customer, 40.00, '2040-01-04 01:00:00'),
        ('V_' + marker + '_5', normal_customer, 50.00, '2040-01-05 01:00:00'),
        ('V_' + marker + '_q1', injection_customer, 7.50, '2041-02-01 00:00:00'),
        ('V_' + marker + '_q2', injection_customer, 8.25, '2041-02-02 00:00:00'),
    ]
    conn = sqlite3.connect(DB_PATH)
    conn.executemany(
        'INSERT INTO orders(order_id, customer_id, amount, order_date) VALUES (?, ?, ?, ?)', rows
    )
    conn.commit()
    conn.close()

    for customer_id, page, page_size in [
        (normal_customer, 1, 2),
        (normal_customer, 2, 2),
        (normal_customer, 3, 2),
        (normal_customer, 1, 4),
        (injection_customer, 1, 10),
        ('MISSING_' + marker, 1, 3),
    ]:
        actual = api.get_customer_summary(DB_PATH, customer_id, page, page_size)
        assert_summary(actual, expected_summary(customer_id, page, page_size))

    source = open(API_PATH, encoding='utf-8').read()
    tree = ast.parse(source, API_PATH)
    parameterized_execute = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr in ('execute', 'executemany'):
            if len(node.args) >= 2 or any(k.arg in ('parameters', 'params') for k in node.keywords):
                parameterized_execute = True
            if node.args and isinstance(node.args[0], (ast.JoinedStr, ast.BinOp)):
                pytest.fail('SQL must not be constructed using string interpolation in execute().')
    assert parameterized_execute, 'query_api.py does not contain a parameterized execute call.'


def test_benchmark_artifacts_are_executable():
    assert os.path.isfile(BENCHMARK_PATH), 'Benchmark /home/user/benchmark.py not found.'
    source = open(BENCHMARK_PATH, encoding='utf-8').read()
    assert 'multiprocessing' in source, 'Benchmark must use multiprocessing.'
    assert 'get_customer_summary' in source, 'Benchmark must call get_customer_summary.'
    assert 'execution_time.txt' in source, 'Benchmark must write execution_time.txt.'
    assert '500' in source and '4' in source, 'Benchmark must run 4 readers with 500 calls each.'
    assert 'insert' in source.lower(), 'Benchmark must include a writer that inserts rows.'

    if os.path.exists(METRIC_PATH):
        os.remove(METRIC_PATH)
    process = subprocess.Popen(
        [sys.executable, BENCHMARK_PATH],
        cwd='/home/user', stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=45)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        pytest.fail('benchmark.py did not terminate within 45 seconds.')
    assert process.returncode == 0, f'benchmark.py failed:\n{stdout}\n{stderr}'
    assert os.path.isfile(METRIC_PATH), 'benchmark.py did not create execution_time.txt.'
    text = open(METRIC_PATH, encoding='utf-8').read().strip()
    try:
        metric = float(text)
    except ValueError:
        pytest.fail(f'execution_time.txt is not a simple float: {text!r}')
    assert math.isfinite(metric) and metric >= 0, 'Execution time must be a finite non-negative float.'


def test_performance_metric():
    global PERF_CASES, PERF_ID_DATES
    conn = sqlite3.connect(DB_PATH)
    customers = [row[0] for row in conn.execute(
        'SELECT customer_id FROM orders GROUP BY customer_id HAVING COUNT(*) >= 20 ORDER BY customer_id LIMIT 8'
    )]
    assert len(customers) >= 4, 'Not enough loaded customers for the concurrency benchmark.'

    PERF_CASES = []
    PERF_ID_DATES = {}
    for customer_number, customer_id in enumerate(customers):
        total, spent = conn.execute(
            'SELECT COUNT(*), COALESCE(SUM(amount), 0) FROM orders WHERE customer_id = ?',
            (customer_id,),
        ).fetchone()
        all_rows = conn.execute(
            'SELECT order_id, order_date FROM orders WHERE customer_id = ? ORDER BY order_date DESC',
            (customer_id,),
        ).fetchall()
        for order_id, order_date in all_rows:
            PERF_ID_DATES[order_id] = order_date
        page_size = 3 + (customer_number % 8)
        page = 1 + (customer_number % 4)
        offset = (page - 1) * page_size
        expected_dates = sorted([row[1] for row in all_rows], reverse=True)[offset:offset + page_size]
        PERF_CASES.append((customer_id, page, page_size, total, float(spent or 0), expected_dates))
    conn.close()

    start = time.time()
    processes = [multiprocessing.Process(target=worker, args=(i,)) for i in range(4)]
    for process in processes:
        process.start()
    for process in processes:
        process.join()
    duration = time.time() - start

    for process in processes:
        assert process.exitcode == 0, f'A worker process failed with exit code {process.exitcode}'
    assert duration <= 2.0, f'Performance metric failed: execution time {duration:.3f}s > 2.0s threshold.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
