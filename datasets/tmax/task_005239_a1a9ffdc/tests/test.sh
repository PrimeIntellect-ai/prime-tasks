#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/sqlite_audit
cat << 'AUDIT_EOF' > /tmp/sqlite_audit/sqlite3.py
from _sqlite3 import *
import _sqlite3
import json
import os

_REAL_CONNECT = _sqlite3.connect
_MISSING = object()

def _contains(value, wanted):
    if value == wanted:
        return True
    if isinstance(value, dict):
        return any(_contains(v, wanted) for v in value.values())
    if isinstance(value, (list, tuple)):
        return any(_contains(v, wanted) for v in value)
    return False

def _jsonable(value):
    if isinstance(value, dict):
        return {str(k): _jsonable(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_jsonable(v) for v in value]
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    return repr(value)

def _record(sql, parameters):
    path = os.environ.get('SQLITE_AUDIT_LOG')
    if not path:
        return
    category = os.environ.get('SQLITE_AUDIT_CATEGORY')
    entry = {
        'sql': str(sql),
        'has_parameters': parameters is not _MISSING,
        'binds_category': parameters is not _MISSING and _contains(parameters, category),
        'parameters': None if parameters is _MISSING else _jsonable(parameters),
    }
    with open(path, 'a') as f:
        f.write(json.dumps(entry) + '\n')

class CursorWrapper:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, parameters=_MISSING):
        _record(sql, parameters)
        if parameters is _MISSING:
            self._cursor.execute(sql)
        else:
            self._cursor.execute(sql, parameters)
        return self

    def executemany(self, sql, seq_of_parameters):
        return self._cursor.executemany(sql, seq_of_parameters)

    def executescript(self, sql_script):
        return self._cursor.executescript(sql_script)

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

class ConnectionWrapper:
    def __init__(self, connection):
        self._connection = connection

    def cursor(self, *args, **kwargs):
        return CursorWrapper(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, parameters=_MISSING):
        _record(sql, parameters)
        if parameters is _MISSING:
            return CursorWrapper(self._connection.execute(sql))
        return CursorWrapper(self._connection.execute(sql, parameters))

    def executemany(self, sql, seq_of_parameters):
        return CursorWrapper(self._connection.executemany(sql, seq_of_parameters))

    def executescript(self, sql_script):
        return CursorWrapper(self._connection.executescript(sql_script))

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)

def connect(*args, **kwargs):
    return ConnectionWrapper(_REAL_CONNECT(*args, **kwargs))
AUDIT_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
import pytest

DB_PATH = "/home/user/ecommerce.db"
SQL_PATH = "/home/user/schema_optimization.sql"
SCRIPT_PATH = "/home/user/generate_report.py"
REPORT_PATH = "/home/user/report.json"
REQUIRED_INDEXES = {
    ("orders", "user_id"),
    ("order_items", "order_id"),
    ("order_items", "product_id"),
    ("products", "category"),
}

def strip_sql_comments(text):
    out = []
    i = 0
    quote = None
    while i < len(text):
        ch = text[i]
        if quote:
            out.append(ch)
            if ch == quote:
                if i + 1 < len(text) and text[i + 1] == quote:
                    out.append(text[i + 1])
                    i += 2
                    continue
                quote = None
            i += 1
            continue
        if ch in ("'", '"', '`'):
            quote = ch
            out.append(ch)
            i += 1
        elif text.startswith('--', i):
            end = text.find('\n', i + 2)
            if end == -1:
                break
            out.append('\n')
            i = end + 1
        elif text.startswith('/*', i):
            end = text.find('*/', i + 2)
            assert end != -1, "Unterminated SQL comment"
            out.append(' ')
            i = end + 2
        else:
            out.append(ch)
            i += 1
    return ''.join(out)

def split_sql_statements(text):
    statements = []
    current = ''
    for ch in text:
        current += ch
        if ch == ';' and sqlite3.complete_statement(current):
            if current.strip():
                statements.append(current.strip())
            current = ''
    if current.strip():
        candidate = current.strip() + ';'
        assert sqlite3.complete_statement(candidate), "Incomplete SQL statement in optimization file"
        statements.append(current.strip())
    return statements

def first_columns_by_table(conn):
    found = set()
    for table in ("orders", "order_items", "products"):
        for row in conn.execute(f'PRAGMA index_list("{table}")'):
            name = row[1]
            escaped = name.replace('"', '""')
            columns = list(conn.execute(f'PRAGMA index_info("{escaped}")'))
            if columns and columns[0][2] is not None:
                found.add((table, str(columns[0][2]).lower()))
    return found

def expected_report(category):
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute('''
        SELECT u.id, u.name, SUM(oi.quantity * p.price) AS total_spend
        FROM users u
        JOIN orders o ON u.id = o.user_id
        JOIN order_items oi ON o.id = oi.order_id
        JOIN products p ON oi.product_id = p.id
        WHERE p.category = ?
        GROUP BY u.id, u.name
        HAVING total_spend > 0
        ORDER BY total_spend DESC
        LIMIT 5
    ''', (category,)).fetchall()
    conn.close()
    return [{"user_id": r[0], "name": r[1], "total_spend": round(r[2], 2)} for r in rows]

def assert_report(actual, expected):
    assert isinstance(actual, list), "report.json must contain a JSON list"
    assert len(actual) == len(expected), f"Expected {len(expected)} report rows, found {len(actual)}"
    for rank, (got, wanted) in enumerate(zip(actual, expected), 1):
        assert isinstance(got, dict), f"Report row {rank} is not an object"
        assert set(got) == {"user_id", "name", "total_spend"}, f"Report row {rank} has the wrong JSON structure"
        assert got["user_id"] == wanted["user_id"], f"Wrong user_id at rank {rank}"
        assert got["name"] == wanted["name"], f"Wrong name at rank {rank}"
        assert abs(got["total_spend"] - wanted["total_spend"]) < 0.01, f"Wrong total_spend at rank {rank}"

def test_schema_optimization_sql():
    assert os.path.exists(SQL_PATH), f"SQL file {SQL_PATH} does not exist."
    content = open(SQL_PATH).read()

    # Preserve the original assertion.
    index_count = content.lower().count("create index")
    assert index_count >= 3, f"Expected at least 3 CREATE INDEX statements in {SQL_PATH}, found {index_count}."

    effective = strip_sql_comments(content)
    statements = split_sql_statements(effective)
    assert statements, "The optimization SQL file contains no executable statements"
    for statement in statements:
        assert re.match(r'^\s*CREATE\s+(?:UNIQUE\s+)?INDEX\b', statement, re.I), \
            "schema_optimization.sql may contain only CREATE INDEX statements"

    check = sqlite3.connect(':memory:')
    check.executescript('''
        CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
        CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, category TEXT, price REAL);
        CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER);
        CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER, product_id INTEGER, quantity INTEGER);
    ''')
    for statement in statements:
        check.execute(statement)
    present = first_columns_by_table(check)
    check.close()
    missing = REQUIRED_INDEXES - present
    assert not missing, f"Optimization SQL is missing effective indexes beginning with these columns: {sorted(missing)}"

def test_database_indexes():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."
    conn = sqlite3.connect(DB_PATH)
    indexes = conn.execute("SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%'").fetchall()
    assert len(indexes) >= 3, f"Expected at least 3 custom indexes in the database, found {len(indexes)}."
    present = first_columns_by_table(conn)
    conn.close()
    missing = REQUIRED_INDEXES - present
    assert not missing, f"Database is missing effective indexes beginning with these columns: {sorted(missing)}"

def test_python_script_updated():
    assert os.path.exists(SCRIPT_PATH), f"Python script {SCRIPT_PATH} does not exist."
    content = open(SCRIPT_PATH).read()
    assert "(SELECT SUM(oi.quantity * p.price)" not in content, "The script still contains the inefficient correlated subquery."
    assert "GROUP BY" in content.upper(), "The script does not seem to use GROUP BY as requested."

def run_and_audit(category):
    log_path = '/tmp/sqlite-query-audit.jsonl'
    if os.path.exists(log_path):
        os.remove(log_path)
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    env = os.environ.copy()
    env['PYTHONPATH'] = '/tmp/sqlite_audit'
    env['SQLITE_AUDIT_LOG'] = log_path
    env['SQLITE_AUDIT_CATEGORY'] = category
    result = subprocess.run(
        ['python3', SCRIPT_PATH, category], cwd='/home/user', env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, f"generate_report.py failed for {category!r}: {result.stderr}"
    assert os.path.exists(REPORT_PATH), "The script did not create report.json"
    try:
        actual = json.load(open(REPORT_PATH))
    except json.JSONDecodeError as exc:
        pytest.fail(f"report.json is invalid JSON: {exc}")
    expected = expected_report(category)
    assert_report(actual, expected)

    assert os.path.exists(log_path), "No SQLite query was executed by generate_report.py"
    entries = [json.loads(line) for line in open(log_path) if line.strip()]
    candidates = []
    for entry in entries:
        cleaned = strip_sql_comments(entry['sql'])
        lower = cleaned.lower()
        if (re.search(r'\bselect\b', lower) and re.search(r'\busers\b', lower)
                and re.search(r'\borders\b', lower) and re.search(r'\border_items\b', lower)
                and re.search(r'\bproducts\b', lower)):
            candidates.append((entry, cleaned))
    assert candidates, "The script did not execute a report query joining the required tables"

    for entry, cleaned in candidates:
        lower = cleaned.lower()
        assert len(re.findall(r'\bjoin\b', lower)) >= 3, "Report query must use standard JOINs for all relationships"
        assert re.search(r'\bgroup\s+by\b', lower), "Executed report query does not use GROUP BY"
        assert category.lower() not in lower, "Category was hardcoded into the SQL text"
        assert entry['has_parameters'] and entry['binds_category'], "Category was not supplied as a bound SQL parameter"
        params = entry['parameters']
        conn = sqlite3.connect(DB_PATH)
        try:
            plan = conn.execute('EXPLAIN QUERY PLAN ' + entry['sql'], params).fetchall()
        finally:
            conn.close()
        detail = ' '.join(str(row[3]) for row in plan).upper()
        assert 'CORRELATED' not in detail, "Executed report query still uses a correlated subquery"

def test_report_json_output_and_query_execution():
    # Exercise normal categories and an injection-shaped value rather than trusting a prebuilt report.
    run_and_audit('Electronics')
    run_and_audit('Clothing')
    run_and_audit("Electronics' OR 1=1 --")
    # Leave the required final Electronics report in place.
    run_and_audit('Electronics')
    assert len(json.load(open(REPORT_PATH))) == 5, f"Expected 5 results in {REPORT_PATH}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
