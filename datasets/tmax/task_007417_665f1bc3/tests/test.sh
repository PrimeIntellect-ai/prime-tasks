#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/instrument_runner.py
import atexit
import json
import runpy
import sqlite3
import sys

script_path, year, log_path = sys.argv[1:4]
real_connect = sqlite3.connect
events = []
_missing = object()

def serializable(value):
    if isinstance(value, dict):
        return {str(k): serializable(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [serializable(v) for v in value]
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    try:
        return [serializable(v) for v in value]
    except TypeError:
        return repr(value)

def record(sql, parameters):
    events.append({
        "sql": str(sql),
        "parameters": None if parameters is _missing else serializable(parameters),
    })

class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, parameters=_missing):
        record(sql, parameters)
        if parameters is _missing:
            self._cursor.execute(sql)
        else:
            self._cursor.execute(sql, parameters)
        return self

    def executemany(self, sql, seq_of_parameters):
        params = list(seq_of_parameters)
        record(sql, params)
        self._cursor.executemany(sql, params)
        return self

    def executescript(self, sql):
        record(sql, _missing)
        self._cursor.executescript(sql)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

class ConnectionProxy:
    def __init__(self, connection):
        object.__setattr__(self, "_connection", connection)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, parameters=_missing):
        cursor = self.cursor()
        return cursor.execute(sql, parameters)

    def executemany(self, sql, seq_of_parameters):
        cursor = self.cursor()
        return cursor.executemany(sql, seq_of_parameters)

    def executescript(self, sql):
        cursor = self.cursor()
        return cursor.executescript(sql)

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)

    def __setattr__(self, name, value):
        setattr(self._connection, name, value)

def monitored_connect(*args, **kwargs):
    return ConnectionProxy(real_connect(*args, **kwargs))

def write_log():
    with open(log_path, "w") as f:
        json.dump(events, f)

atexit.register(write_log)
sqlite3.connect = monitored_connect
sys.argv = [script_path, year]
runpy.run_path(script_path, run_name="__main__")
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import sys

import pytest

SCRIPT_PATH = '/home/user/analyze_high_value_users.py'
REPORT_PATH = '/home/user/report.json'
DB_PATH = '/home/user/ecommerce.db'
RUNNER_PATH = '/tmp/instrument_runner.py'
EXPECTED_KEYS = {
    'target_year',
    'eligible_users_count',
    'eligible_orders_count',
    'total_electronics_spend',
    'total_electronics_quantity',
}


def expected_report(target_year):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    c.execute("SELECT user_id FROM users WHERE reg_year = ?", (target_year,))
    user_ids = [row[0] for row in c.fetchall()]
    expected_users_count = len(user_ids)

    if not user_ids:
        expected_orders_count = 0
        order_ids = []
    else:
        placeholders = ','.join('?' * len(user_ids))
        c.execute(
            f"SELECT order_id FROM orders WHERE user_id IN ({placeholders}) AND total > 100.0",
            user_ids,
        )
        order_ids = [row[0] for row in c.fetchall()]
        expected_orders_count = len(order_ids)

    if not order_ids:
        expected_spend = 0.0
        expected_qty = 0
    else:
        placeholders = ','.join('?' * len(order_ids))
        c.execute(
            f"SELECT SUM(price * quantity), SUM(quantity) FROM order_items "
            f"WHERE order_id IN ({placeholders}) AND category = 'Electronics'",
            order_ids,
        )
        row = c.fetchone()
        expected_spend = float(row[0]) if row[0] is not None else 0.0
        expected_qty = int(row[1]) if row[1] is not None else 0

    conn.close()
    return {
        'target_year': target_year,
        'eligible_users_count': expected_users_count,
        'eligible_orders_count': expected_orders_count,
        'total_electronics_spend': expected_spend,
        'total_electronics_quantity': expected_qty,
    }, user_ids, order_ids


def read_report():
    assert os.path.exists(REPORT_PATH), f"Report missing at {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"Expected a file at {REPORT_PATH}"
    with open(REPORT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON.")


def assert_report(report, expected):
    assert set(report) == EXPECTED_KEYS, f"Report must contain exactly {sorted(EXPECTED_KEYS)}"
    assert "target_year" in report, "Missing 'target_year' in report"
    assert report["target_year"] == expected['target_year'], (
        f"Expected target_year {expected['target_year']}, got {report['target_year']}"
    )
    assert "eligible_users_count" in report, "Missing 'eligible_users_count' in report"
    assert report["eligible_users_count"] == expected['eligible_users_count'], (
        f"Expected {expected['eligible_users_count']} eligible users, got {report['eligible_users_count']}"
    )
    assert "eligible_orders_count" in report, "Missing 'eligible_orders_count' in report"
    assert report["eligible_orders_count"] == expected['eligible_orders_count'], (
        f"Expected {expected['eligible_orders_count']} eligible orders, got {report['eligible_orders_count']}"
    )
    assert "total_electronics_spend" in report, "Missing 'total_electronics_spend' in report"
    assert float(report["total_electronics_spend"]) == expected['total_electronics_spend'], (
        f"Expected total_electronics_spend {expected['total_electronics_spend']}, "
        f"got {report['total_electronics_spend']}"
    )
    assert "total_electronics_quantity" in report, "Missing 'total_electronics_quantity' in report"
    assert int(report["total_electronics_quantity"]) == expected['total_electronics_quantity'], (
        f"Expected total_electronics_quantity {expected['total_electronics_quantity']}, "
        f"got {report['total_electronics_quantity']}"
    )


def run_script(year, instrument=False):
    if instrument:
        log_path = f"/tmp/sql-events-{year}-{secrets.token_hex(4)}.json"
        cmd = [sys.executable, RUNNER_PATH, SCRIPT_PATH, str(year), log_path]
    else:
        log_path = None
        cmd = [sys.executable, SCRIPT_PATH, str(year)]

    result = subprocess.run(cmd, text=True, capture_output=True, timeout=20)
    assert result.returncode == 0, (
        f"Script failed for year {year}. stdout={result.stdout!r} stderr={result.stderr!r}"
    )
    if log_path is None:
        return None
    assert os.path.isfile(log_path), "SQL instrumentation log was not produced"
    with open(log_path) as f:
        return json.load(f)


def flattened_parameters(event):
    value = event['parameters']
    if isinstance(value, dict):
        return list(value.values())
    if isinstance(value, list):
        result = []
        for item in value:
            if isinstance(item, list):
                result.extend(item)
            else:
                result.append(item)
        return result
    if value is None:
        return []
    return [value]


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Expected a file at {SCRIPT_PATH}"


def test_report_exists():
    assert os.path.exists(REPORT_PATH), f"Report missing at {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"Expected a file at {REPORT_PATH}"


def test_report_contents():
    assert os.path.exists(DB_PATH), f"Database missing at {DB_PATH}"
    run_script(2022)
    expected, _, _ = expected_report(2022)
    assert_report(read_report(), expected)


def test_dynamic_pipeline_and_parameterized_queries():
    backup = f"/tmp/ecommerce-{secrets.token_hex(8)}.db"
    shutil.copy2(DB_PATH, backup)
    target_year = 2400 + secrets.randbelow(500)
    empty_year = target_year + 1000

    conn = sqlite3.connect(DB_PATH)
    try:
        c = conn.cursor()
        next_user = c.execute("SELECT COALESCE(MAX(user_id), 0) + 100 FROM users").fetchone()[0]
        next_order = c.execute("SELECT COALESCE(MAX(order_id), 0) + 100 FROM orders").fetchone()[0]
        next_item = c.execute("SELECT COALESCE(MAX(item_id), 0) + 100 FROM order_items").fetchone()[0]
        user_ids = [next_user, next_user + 1]
        high_order_ids = [next_order, next_order + 2]

        c.executemany(
            "INSERT INTO users(user_id, name, reg_year) VALUES (?, ?, ?)",
            [(user_ids[0], 'Dynamic A', target_year), (user_ids[1], 'Dynamic B', target_year)],
        )
        c.executemany(
            "INSERT INTO orders(order_id, user_id, total) VALUES (?, ?, ?)",
            [
                (next_order, user_ids[0], 173.0),
                (next_order + 1, user_ids[0], 100.0),
                (next_order + 2, user_ids[1], 251.0),
            ],
        )
        c.executemany(
            "INSERT INTO order_items(item_id, order_id, category, price, quantity) VALUES (?, ?, ?, ?, ?)",
            [
                (next_item, next_order, 'Electronics', 37.0, 3),
                (next_item + 1, next_order, 'Books', 99.0, 8),
                (next_item + 2, next_order + 1, 'Electronics', 500.0, 2),
                (next_item + 3, next_order + 2, 'Electronics', 19.0, 7),
            ],
        )
        conn.commit()
    finally:
        conn.close()

    try:
        expected, expected_users, expected_orders = expected_report(target_year)
        events = run_script(target_year, instrument=True)
        assert_report(read_report(), expected)

        relevant = []
        for event in events:
            sql = event['sql']
            lower = sql.lower()
            tables = [name for name in ('users', 'orders', 'order_items') if re.search(r'\b' + name + r'\b', lower)]
            if tables and re.search(r'\bselect\b', lower):
                relevant.append((event, tables))

        assert len(relevant) == 3, (
            "The program must perform the requested three-query pipeline; "
            f"observed {len(relevant)} SELECTs involving pipeline tables"
        )
        assert relevant[0][1] == ['users'], "Query 1 must query only the users table"
        assert relevant[1][1] == ['orders'], "Query 2 must query only the orders table"
        assert relevant[2][1] == ['order_items'], "Query 3 must query only the order_items table"

        q1, q2, q3 = [entry[0] for entry in relevant]
        q1_params = flattened_parameters(q1)
        q2_params = flattened_parameters(q2)
        q3_params = flattened_parameters(q3)

        assert target_year in q1_params, "Query 1 must bind the command-line year as a SQL parameter"
        assert all(uid in q2_params for uid in expected_users), (
            "Query 2 must dynamically bind all user IDs fetched by Query 1"
        )
        assert all(oid in q3_params for oid in expected_orders), (
            "Query 3 must dynamically bind all order IDs fetched by Query 2"
        )

        for value, event, label in [
            (target_year, q1, 'year in Query 1'),
            *[(uid, q2, 'user ID in Query 2') for uid in expected_users],
            *[(oid, q3, 'order ID in Query 3') for oid in expected_orders],
        ]:
            assert str(value) not in event['sql'], f"Dynamic {label} was inserted directly into SQL"

        q3_sql = q3['sql'].lower()
        assert 'sum' in q3_sql and 'price' in q3_sql and 'quantity' in q3_sql, (
            "Query 3 must calculate the requested spend and quantity sums in SQL"
        )

        run_script(empty_year)
        empty_expected, _, _ = expected_report(empty_year)
        assert_report(read_report(), empty_expected)
    finally:
        shutil.copy2(backup, DB_PATH)
        os.remove(backup)
        subprocess.run([sys.executable, SCRIPT_PATH, '2022'], capture_output=True, timeout=20)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
