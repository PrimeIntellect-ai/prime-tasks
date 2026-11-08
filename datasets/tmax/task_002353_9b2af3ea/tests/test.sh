#!/bin/bash
set -e
mkdir -p /logs/verifier

# Install a transparent sqlite3 probe used while report.py runs. It records the
# SQL actually executed while delegating all database work to Python's real
# _sqlite3 extension.
rm -rf /tmp/sqlite_probe
mkdir -p /tmp/sqlite_probe/sqlite3
cat << 'PY_EOF' > /tmp/sqlite_probe/sqlite3/__init__.py
from .dbapi2 import *
PY_EOF
cat << 'PY_EOF' > /tmp/sqlite_probe/sqlite3/dbapi2.py
from _sqlite3 import *
import _sqlite3
import json
import os

_LOG = os.environ.get('SQLITE_PROBE_LOG', '/tmp/report_sql.jsonl')

def _record(sql):
    try:
        with open(_LOG, 'a', encoding='utf-8') as f:
            f.write(json.dumps(str(sql)) + '\n')
    except Exception:
        pass

class CursorProxy:
    def __init__(self, cursor):
        object.__setattr__(self, '_cursor', cursor)

    def execute(self, sql, parameters=()):
        _record(sql)
        self._cursor.execute(sql, parameters)
        return self

    def executemany(self, sql, seq_of_parameters):
        _record(sql)
        self._cursor.executemany(sql, seq_of_parameters)
        return self

    def executescript(self, sql):
        _record(sql)
        self._cursor.executescript(sql)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __next__(self):
        return next(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

    def __setattr__(self, name, value):
        setattr(self._cursor, name, value)

class ConnectionProxy:
    def __init__(self, connection):
        object.__setattr__(self, '_connection', connection)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, parameters=()):
        _record(sql)
        return CursorProxy(self._connection.execute(sql, parameters))

    def executemany(self, sql, seq_of_parameters):
        _record(sql)
        return CursorProxy(self._connection.executemany(sql, seq_of_parameters))

    def executescript(self, sql):
        _record(sql)
        return CursorProxy(self._connection.executescript(sql))

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)

    def __setattr__(self, name, value):
        setattr(self._connection, name, value)

def connect(*args, **kwargs):
    return ConnectionProxy(_sqlite3.connect(*args, **kwargs))
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile

DB_PATH = '/home/user/logistics.db'
OPTIMIZE_SQL_PATH = '/home/user/optimize.sql'
REPORT_PY_PATH = '/home/user/report.py'
METRICS_CSV_PATH = '/home/user/metrics.csv'
PROBE_LOG = '/tmp/report_sql.jsonl'
EXPECTED_HEADER = ['courier_id', 'courier_name', 'recent_avg_time', 'total_5_star_reviews', 'overall_rank']


def get_golden_data():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    query = """
    WITH RecentDeliveries AS (
        SELECT
            courier_id,
            delivery_time_mins,
            AVG(delivery_time_mins) OVER (
                PARTITION BY courier_id
                ORDER BY created_at
                ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
            ) as rolling_avg_time,
            ROW_NUMBER() OVER (
                PARTITION BY courier_id
                ORDER BY created_at DESC
            ) as rn
        FROM deliveries
    ),
    LatestAverages AS (
        SELECT courier_id, rolling_avg_time as recent_avg_time
        FROM RecentDeliveries
        WHERE rn = 1
    ),
    FiveStarCounts AS (
        SELECT d.courier_id, COUNT(r.rating) as total_5_star_reviews
        FROM deliveries d
        JOIN reviews r ON d.id = r.delivery_id
        WHERE r.rating = 5
        GROUP BY d.courier_id
    )
    SELECT
        c.id as courier_id,
        c.name as courier_name,
        ROUND(l.recent_avg_time, 2) as recent_avg_time,
        COALESCE(f.total_5_star_reviews, 0) as total_5_star_reviews,
        DENSE_RANK() OVER (ORDER BY l.recent_avg_time ASC) as overall_rank
    FROM couriers c
    JOIN LatestAverages l ON c.id = l.courier_id
    LEFT JOIN FiveStarCounts f ON c.id = f.courier_id
    ORDER BY overall_rank ASC, courier_id ASC
    LIMIT 10;
    """
    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()
    return rows


def read_and_check_csv(expected_rows):
    assert os.path.isfile(METRICS_CSV_PATH), f"{METRICS_CSV_PATH} is missing."
    with open(METRICS_CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == EXPECTED_HEADER, 'CSV header does not match the expected format.'
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(actual_rows)}."
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert len(actual) == 5, f"Row {i+1} does not have exactly five columns."
        assert int(actual[0]) == expected[0], f"Row {i+1}: expected courier_id {expected[0]}, got {actual[0]}"
        assert actual[1] == expected[1], f"Row {i+1}: expected courier_name {expected[1]}, got {actual[1]}"
        assert float(actual[2]) == expected[2], f"Row {i+1}: expected recent_avg_time {expected[2]}, got {actual[2]}"
        assert int(actual[3]) == expected[3], f"Row {i+1}: expected total_5_star_reviews {expected[3]}, got {actual[3]}"
        assert int(actual[4]) == expected[4], f"Row {i+1}: expected overall_rank {expected[4]}, got {actual[4]}"
    return actual_rows


def strip_sql_comments(sql):
    sql = re.sub(r'/\*.*?\*/', ' ', sql, flags=re.S)
    sql = re.sub(r'--[^\n]*', ' ', sql)
    return sql


def run_report_and_validate_query(expected_rows):
    if os.path.exists(METRICS_CSV_PATH):
        os.remove(METRICS_CSV_PATH)
    if os.path.exists(PROBE_LOG):
        os.remove(PROBE_LOG)

    env = os.environ.copy()
    env['PYTHONPATH'] = '/tmp/sqlite_probe' + (':' + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    env['SQLITE_PROBE_LOG'] = PROBE_LOG
    result = subprocess.run(
        ['python3', REPORT_PY_PATH], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"report.py failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert os.path.isfile(PROBE_LOG), 'report.py did not connect through Python sqlite3 or execute any SQL.'

    with open(PROBE_LOG, encoding='utf-8') as f:
        statements = [json.loads(line) for line in f if line.strip()]
    read_queries = []
    for statement in statements:
        cleaned = strip_sql_comments(statement).strip()
        if re.match(r'^(with\b|select\b)', cleaned, flags=re.I):
            read_queries.append(cleaned)

    assert len(read_queries) == 1, f"report.py must execute one reporting query; observed {len(read_queries)} SELECT/WITH queries."
    query = re.sub(r'\s+', ' ', read_queries[0]).lower()
    assert re.search(r'\bavg\s*\([^)]*\)\s*over\s*\(', query), 'The executed query does not calculate the rolling average with a window function.'
    assert re.search(r'\brow_number\s*\(\s*\)\s*over\s*\(', query), 'The executed query does not use ROW_NUMBER() to select the latest moving average.'
    assert re.search(r'\bdense_rank\s*\(\s*\)\s*over\s*\(', query), 'The executed query does not use DENSE_RANK().'
    assert re.search(r'\brows\s+(?:between\s+)?4\s+preceding\b', query), 'The rolling window is not limited to the current and four preceding deliveries.'
    assert re.search(r'\bcount\s*\(', query), 'The executed query does not aggregate review counts.'
    assert re.search(r'\bjoin\b', query), 'The executed query does not join the reporting tables.'
    assert re.search(r'\bgroup\s+by\b', query), 'The executed query does not perform the required grouped aggregation.'
    assert re.search(r'\brating\s*=\s*5\b|\b5\s*=\s*[^ ]*rating\b', query), 'The executed query does not restrict the review count to 5-star ratings.'
    return read_and_check_csv(expected_rows)


def test_optimize_sql_exists():
    assert os.path.isfile(OPTIMIZE_SQL_PATH), f"{OPTIMIZE_SQL_PATH} is missing."


def test_optimize_sql_creates_indexes():
    with open(OPTIMIZE_SQL_PATH, 'r') as f:
        sql_content = f.read()
    lowered = sql_content.lower()

    # Preserve the original textual assertions.
    assert 'create index' in lowered, f"No CREATE INDEX statements found in {OPTIMIZE_SQL_PATH}"
    assert 'deliveries' in lowered, f"No index on deliveries table found in {OPTIMIZE_SQL_PATH}"
    assert 'reviews' in lowered, f"No index on reviews table found in {OPTIMIZE_SQL_PATH}"

    # Execute the submitted script against a clean copy of the required schema,
    # then inspect the indexes it really creates.
    conn = sqlite3.connect(':memory:')
    conn.executescript('''
        CREATE TABLE couriers (id INTEGER PRIMARY KEY, name TEXT);
        CREATE TABLE deliveries (id INTEGER PRIMARY KEY, courier_id INTEGER, delivery_time_mins INTEGER, created_at DATETIME);
        CREATE TABLE reviews (delivery_id INTEGER PRIMARY KEY, rating INTEGER);
    ''')
    try:
        conn.executescript(sql_content)
    except sqlite3.Error as exc:
        raise AssertionError(f"optimize.sql is not valid executable SQL: {exc}")

    def user_indexes(table):
        result = []
        for row in conn.execute(f"PRAGMA index_list('{table}')"):
            name = row[1]
            if not name.startswith('sqlite_autoindex'):
                cols = [x[2].lower() for x in conn.execute(f"PRAGMA index_info('{name}')")]
                result.append((name, cols))
        return result

    delivery_indexes = user_indexes('deliveries')
    review_indexes = user_indexes('reviews')
    assert any(cols[:2] == ['courier_id', 'created_at'] for _, cols in delivery_indexes), \
        'optimize.sql must create a deliveries index beginning with (courier_id, created_at).'
    assert any(cols and cols[0] == 'rating' for _, cols in review_indexes), \
        'optimize.sql must create a reviews index beginning with rating for filtering 5-star reviews.'
    conn.close()


def test_report_py_exists():
    assert os.path.isfile(REPORT_PY_PATH), f"{REPORT_PY_PATH} is missing."


def test_metrics_csv_correctness_and_report_execution():
    baseline_expected = get_golden_data()
    baseline_actual = run_report_and_validate_query(baseline_expected)

    # Change the source data and require report.py to regenerate a correspondingly
    # changed result, preventing a hardcoded CSV or an unrelated generator.
    fd, backup_path = tempfile.mkstemp(prefix='logistics-backup-', suffix='.db')
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute('UPDATE deliveries SET delivery_time_mins = 1 WHERE courier_id = 50')
        conn.execute('INSERT OR REPLACE INTO reviews(delivery_id, rating) SELECT id, 5 FROM deliveries WHERE courier_id = 50')
        conn.commit()
        conn.close()

        changed_expected = get_golden_data()
        assert changed_expected != baseline_expected, 'Verifier perturbation unexpectedly did not change the expected report.'
        changed_actual = run_report_and_validate_query(changed_expected)
        assert changed_actual != baseline_actual, 'metrics.csv did not respond to changed database contents.'
    finally:
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)

    # Leave metrics.csv correctly generated for the original database.
    run_report_and_validate_query(get_golden_data())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
