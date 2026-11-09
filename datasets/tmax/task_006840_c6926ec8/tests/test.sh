#!/bin/bash
set -e
mkdir -p /logs/verifier

DB_PATH=/home/user/compliance.db
DB_BACKUP=$(mktemp)
cp -f "$DB_PATH" "$DB_BACKUP"
trap 'cp -f "$DB_BACKUP" "$DB_PATH" 2>/dev/null || true; rm -f "$DB_BACKUP"' EXIT

cat << 'RUNNER_EOF' > /tmp/run_audit_tracked.py
import json
import runpy
import sqlite3

log_path = '/tmp/audit_sql_log.json'
statements = []
real_connect = sqlite3.connect


def serializable_params(params):
    try:
        value = list(params)
        json.dumps(value)
        return value
    except Exception:
        return None


class TrackedCursor:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, parameters=()):
        statements.append({'sql': str(sql), 'params': serializable_params(parameters)})
        self._cursor.execute(sql, parameters)
        return self

    def executemany(self, sql, seq_of_parameters):
        values = list(seq_of_parameters)
        statements.append({'sql': str(sql), 'params': None})
        self._cursor.executemany(sql, values)
        return self

    def executescript(self, sql):
        statements.append({'sql': str(sql), 'params': None})
        self._cursor.executescript(sql)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)


class TrackedConnection:
    def __init__(self, connection):
        self._connection = connection

    def cursor(self, *args, **kwargs):
        return TrackedCursor(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, parameters=()):
        statements.append({'sql': str(sql), 'params': serializable_params(parameters)})
        return TrackedCursor(self._connection.execute(sql, parameters))

    def executemany(self, sql, seq_of_parameters):
        values = list(seq_of_parameters)
        statements.append({'sql': str(sql), 'params': None})
        return TrackedCursor(self._connection.executemany(sql, values))

    def executescript(self, sql):
        statements.append({'sql': str(sql), 'params': None})
        return TrackedCursor(self._connection.executescript(sql))

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)


def tracked_connect(*args, **kwargs):
    return TrackedConnection(real_connect(*args, **kwargs))


sqlite3.connect = tracked_connect
try:
    runpy.run_path('/home/user/audit.py', run_name='__main__')
finally:
    with open(log_path, 'w') as f:
        json.dump(statements, f)
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import shutil
import sqlite3
import subprocess

DB_PATH = '/home/user/compliance.db'
CSV_PATH = '/home/user/flagged_paths.csv'
SCRIPT_PATH = '/home/user/audit.py'
LOG_PATH = '/tmp/audit_sql_log.json'
HEADER = ['A_name', 'B_name', 'C_name', 't1_amount', 't2_amount']

FIXTURES = [
    (
        [
            (1, 'Alice', 'Internal'),
            (2, 'Bob', 'External'),
            (3, 'Charlie', 'Internal'),
            (4, 'Dave', 'External'),
            (5, 'Eve', 'Internal'),
            (6, 'Frank', 'External'),
        ],
        [
            (1, 1, 2, 100, '2023-01-01'),
            (2, 2, 3, 200, '2023-01-02'),
            (3, 2, 4, 50, '2023-01-03'),
            (4, 3, 4, 150, '2023-01-04'),
            (5, 4, 1, 300, '2023-01-05'),
            (6, 4, 5, 100, '2023-01-06'),
            (7, 5, 6, 80, '2023-01-07'),
            (8, 6, 5, 50, '2023-01-08'),
            (9, 6, 1, 50, '2023-01-09'),
        ],
    ),
    (
        [
            (1, 'Zed', 'Internal'),
            (2, 'Bridge', 'External'),
            (3, 'Alpha', 'Internal'),
            (4, 'Other', 'Internal'),
            (5, 'Solo', 'External'),
        ],
        [
            (1, 1, 2, 10, '2024-01-01'),
            (2, 3, 2, 20, '2024-01-02'),
            (3, 2, 3, 90, '2024-01-03'),
            (4, 2, 4, 30, '2024-01-04'),
            (5, 4, 5, 12, '2024-01-05'),
            (6, 5, 1, 50, '2024-01-06'),
        ],
    ),
]

EXPECTED_QUERY = '''
WITH B_Avg AS (
    SELECT source_id, AVG(amount) AS avg_amount
    FROM transactions
    GROUP BY source_id
)
SELECT A.name, B.name, C.name, t1.amount, t2.amount
FROM transactions t1
JOIN transactions t2 ON t1.target_id = t2.source_id
JOIN entities A ON t1.source_id = A.id
JOIN entities B ON t1.target_id = B.id
JOIN entities C ON t2.target_id = C.id
JOIN B_Avg ON B.id = B_Avg.source_id
WHERE A.domain = C.domain
  AND A.domain != B.domain
  AND t2.amount > B_Avg.avg_amount
ORDER BY t2.amount DESC, A.name ASC
'''


def create_fixture(entities, transactions):
    if os.path.lexists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    conn.executescript('''
        CREATE TABLE entities (id INTEGER PRIMARY KEY, name TEXT, domain TEXT);
        CREATE TABLE transactions (
            tx_id INTEGER PRIMARY KEY,
            source_id INTEGER,
            target_id INTEGER,
            amount REAL,
            tx_date TEXT
        );
    ''')
    conn.executemany('INSERT INTO entities VALUES (?, ?, ?)', entities)
    conn.executemany('INSERT INTO transactions VALUES (?, ?, ?, ?, ?)', transactions)
    conn.commit()
    expected = conn.execute(EXPECTED_QUERY).fetchall()
    conn.close()
    return expected


def strip_sql_comments_and_literals(sql):
    out = []
    i = 0
    while i < len(sql):
        if sql.startswith('--', i):
            end = sql.find('\n', i + 2)
            i = len(sql) if end < 0 else end
        elif sql.startswith('/*', i):
            end = sql.find('*/', i + 2)
            i = len(sql) if end < 0 else end + 2
        elif sql[i] in "'\"":
            quote = sql[i]
            out.append(' ')
            i += 1
            while i < len(sql):
                if sql[i] == quote:
                    if i + 1 < len(sql) and sql[i + 1] == quote:
                        i += 2
                        continue
                    i += 1
                    break
                i += 1
        else:
            out.append(sql[i])
            i += 1
    return ''.join(out)


def is_window_avg(sql):
    cleaned = strip_sql_comments_and_literals(sql)
    return re.search(r'\bAVG\s*\([^)]*\)\s*OVER\s*\(', cleaned, re.I | re.S) is not None


def assert_csv(expected):
    assert os.path.exists(CSV_PATH), f'Expected output file not found: {CSV_PATH}'
    assert os.path.isfile(CSV_PATH), f'Path exists but is not a file: {CSV_PATH}'

    with open(CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == HEADER, f'CSV header is incorrect. Expected {HEADER}, got {header}'
        rows = list(reader)

    assert len(rows) == len(expected), f'Expected {len(expected)} rows in CSV, but found {len(rows)}'
    for i, (actual, wanted) in enumerate(zip(rows, expected)):
        assert len(actual) == 5, f'Row {i + 1} must contain exactly five columns'
        actual_formatted = [actual[0], actual[1], actual[2], str(float(actual[3])), str(float(actual[4]))]
        expected_formatted = [str(wanted[0]), str(wanted[1]), str(wanted[2]), str(float(wanted[3])), str(float(wanted[4]))]
        assert actual_formatted == expected_formatted, (
            f'Row {i + 1} mismatch. Expected {expected_formatted}, got {actual_formatted}'
        )


def query_projects_expected(sql, params, snapshot, expected):
    try:
        conn = sqlite3.connect(snapshot)
        cursor = conn.execute(sql, params or [])
        rows = cursor.fetchall()
        description = cursor.description
        conn.close()
    except Exception:
        return False

    if not description:
        return False
    names = [str(column[0]).lower() for column in description]
    required = [name.lower() for name in HEADER]
    if all(name in names for name in required):
        indexes = [names.index(name) for name in required]
        projected = [tuple(row[index] for index in indexes) for row in rows]
    elif len(description) == 5:
        projected = [tuple(row) for row in rows]
    else:
        return False
    return projected == [tuple(row) for row in expected]


def test_audit_script_uses_window_function_or_cte():
    assert os.path.exists(SCRIPT_PATH), f'Script missing at {SCRIPT_PATH}'
    assert os.path.isfile(SCRIPT_PATH), f'Script path is not a file: {SCRIPT_PATH}'
    with open(SCRIPT_PATH, 'r') as f:
        content = f.read().upper()
    has_window_or_cte = ('AVG(' in content and 'OVER' in content) or ('WITH ' in content and 'AVG(' in content)
    assert has_window_or_cte, 'The script does not appear to use a window function (AVG() OVER (...)) or CTE with AVG() as required.'


def test_script_executes_and_generates_results_from_a_window_query(tmp_path):
    for fixture_number, (entities, transactions) in enumerate(FIXTURES):
        expected = create_fixture(entities, transactions)
        snapshot = str(tmp_path / f'fixture_{fixture_number}.db')
        shutil.copyfile(DB_PATH, snapshot)

        if os.path.lexists(CSV_PATH):
            os.remove(CSV_PATH)
        if os.path.exists(LOG_PATH):
            os.remove(LOG_PATH)

        result = subprocess.run(
            ['python3', '/tmp/run_audit_tracked.py'],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, f'audit.py failed:\n{result.stdout}\n{result.stderr}'
        assert_csv(expected)

        assert os.path.isfile(LOG_PATH), 'No SQL execution log was produced'
        with open(LOG_PATH, 'r') as f:
            statements = json.load(f)
        window_queries = [entry for entry in statements if is_window_avg(entry.get('sql', ''))]
        assert window_queries, 'audit.py did not execute an SQL query using AVG() OVER (...)'
        assert any(
            query_projects_expected(entry['sql'], entry.get('params'), snapshot, expected)
            for entry in window_queries
        ), 'The executed window-function query did not produce the required Domain Hop results'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
