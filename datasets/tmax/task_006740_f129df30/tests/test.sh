#!/bin/bash
set -e
mkdir -p /logs/verifier

STATE_DIR=$(mktemp -d)
cp /home/user/backup_catalog.db "$STATE_DIR/backup_catalog.db"
if [ -f /home/user/backup_report.json ]; then
    cp /home/user/backup_report.json "$STATE_DIR/backup_report.json"
    touch "$STATE_DIR/had_report"
fi
cleanup() {
    cp "$STATE_DIR/backup_catalog.db" /home/user/backup_catalog.db
    if [ -f "$STATE_DIR/had_report" ]; then
        cp "$STATE_DIR/backup_report.json" /home/user/backup_report.json
    else
        rm -f /home/user/backup_report.json
    fi
    rm -rf "$STATE_DIR" /tmp/verifier_hooks /tmp/backup_sql_trace.jsonl /tmp/test_final_state.py
}
trap cleanup EXIT

mkdir -p /tmp/verifier_hooks
cat << 'HOOK_EOF' > /tmp/verifier_hooks/sitecustomize.py
import json
import sqlite3

_REAL_CONNECT = sqlite3.connect
_TRACE_PATH = '/tmp/backup_sql_trace.jsonl'

def _record(sql, params=None):
    try:
        with open(_TRACE_PATH, 'a', encoding='utf-8') as f:
            f.write(json.dumps({'sql': str(sql), 'params': params}, default=str) + '\n')
    except Exception:
        pass

class CursorProxy:
    def __init__(self, cursor):
        object.__setattr__(self, '_cursor', cursor)

    def execute(self, sql, *args):
        _record(sql, args[0] if args else None)
        self._cursor.execute(sql, *args)
        return self

    def executemany(self, sql, seq):
        values = list(seq)
        _record(sql, values)
        self._cursor.executemany(sql, values)
        return self

    def executescript(self, sql):
        _record(sql, None)
        self._cursor.executescript(sql)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

    def __setattr__(self, name, value):
        setattr(self._cursor, name, value)

class ConnectionProxy:
    def __init__(self, connection):
        object.__setattr__(self, '_connection', connection)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, *args):
        _record(sql, args[0] if args else None)
        return CursorProxy(self._connection.execute(sql, *args))

    def executemany(self, sql, seq):
        values = list(seq)
        _record(sql, values)
        return CursorProxy(self._connection.executemany(sql, values))

    def executescript(self, sql):
        _record(sql, None)
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
    return ConnectionProxy(_REAL_CONNECT(*args, **kwargs))

sqlite3.connect = connect
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
import sys
import pytest

SCRIPT_PATH = '/home/user/analyze_backups.py'
REPORT_PATH = '/home/user/backup_report.json'
DB_PATH = '/home/user/backup_catalog.db'
TRACE_PATH = '/tmp/backup_sql_trace.jsonl'
HOOK_PATH = '/tmp/verifier_hooks'


def run_script(region):
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)
    env = os.environ.copy()
    env['PYTHONPATH'] = HOOK_PATH + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH, '--region', region],
        cwd='/home/user', env=env, text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, (
        f"Script failed for region {region!r}. stdout={result.stdout!r} stderr={result.stderr!r}"
    )
    assert os.path.isfile(REPORT_PATH), f"Script did not create {REPORT_PATH}"
    with open(REPORT_PATH, 'r', encoding='utf-8') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON: {exc}")
    traces = []
    if os.path.exists(TRACE_PATH):
        with open(TRACE_PATH, 'r', encoding='utf-8') as f:
            traces = [json.loads(line) for line in f if line.strip()]
    return report, traces


def expected_for(region):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('SELECT id, name FROM clusters WHERE region = ?', (region,))
    clusters = c.fetchall()
    expected = {}
    for cid, cname in clusters:
        c.execute('''
            SELECT id, timestamp
            FROM backups
            WHERE cluster_id = ? AND status = 'SUCCESS'
            ORDER BY timestamp DESC
            LIMIT 1
        ''', (cid,))
        latest = c.fetchone()
        c.execute('''
            SELECT SUM(size_bytes)
            FROM backups
            WHERE cluster_id = ? AND status = 'SUCCESS'
        ''', (cid,))
        total = c.fetchone()[0]
        if latest and total is not None:
            expected[cname] = {
                'latest_backup_id': latest[0],
                'latest_backup_timestamp': latest[1],
                'total_successful_size_bytes': total,
            }
    conn.close()
    return expected


def flattened(value):
    if isinstance(value, dict):
        result = []
        for k, v in value.items():
            result.extend(flattened(k))
            result.extend(flattened(v))
        return result
    if isinstance(value, (list, tuple)):
        result = []
        for item in value:
            result.extend(flattened(item))
        return result
    return [value]


def has_placeholder(sql):
    return bool(re.search(r'\?|:\w+|\$\w+|@\w+', sql))


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file"


def test_script_requirements():
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        content = f.read()

    # Preserve the original implementation checks.
    assert re.search(r'\bLIMIT\b', content, re.IGNORECASE), "Script must use LIMIT for pagination"
    assert re.search(r'\bOFFSET\b', content, re.IGNORECASE), "Script must use OFFSET for pagination"
    assert '?' in content, "Script must use parameterized queries (e.g., '?')"

    # The required total must come from an aggregated GROUP BY query.
    assert re.search(r'\bGROUP\s+BY\b', content, re.IGNORECASE), "Script must use a GROUP BY query"


def test_report_exists_and_content():
    # Preserve the original assertion that the agent generated the requested report.
    assert os.path.exists(REPORT_PATH), f"Report missing at {REPORT_PATH}"

    report_data, _ = run_script('us-west-2')
    assert 'region' in report_data, "Report must contain 'region' key"
    assert report_data['region'] == 'us-west-2', "Report region should be 'us-west-2'"
    assert 'clusters' in report_data, "Report must contain 'clusters' key"

    # Derive expected data from the database, as in the original verifier.
    expected_clusters = expected_for('us-west-2')
    assert report_data['clusters'] == expected_clusters, (
        "Report 'clusters' data does not match the expected derived data"
    )


def test_cli_pagination_parameterization_and_aggregation_on_dynamic_data():
    region = "qa-' OR 1=1 --"
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.executemany('INSERT INTO clusters(id, name, region) VALUES (?, ?, ?)', [
        (20, 'qa-primary', region),
        (21, 'qa-no-success', region),
        (22, 'qa-secondary', region),
    ])

    rows = []
    for i in range(12):
        status = 'FAILED' if i in (11, 7, 3) else 'SUCCESS'
        rows.append((2000 + i, 20, f'2025-01-{i + 1:02d}T10:00:00Z', 100 + i, status))
    rows.extend([
        (2100, 21, '2025-02-01T10:00:00Z', 900, 'FAILED'),
        (2101, 21, '2025-02-02T10:00:00Z', 901, 'FAILED'),
        (2200, 22, '2025-03-01T10:00:00Z', 700, 'SUCCESS'),
        (2201, 22, '2025-03-02T10:00:00Z', 800, 'FAILED'),
        (2202, 22, '2025-03-03T10:00:00Z', 900, 'SUCCESS'),
    ])
    c.executemany(
        'INSERT INTO backups(id, cluster_id, timestamp, size_bytes, status) VALUES (?, ?, ?, ?, ?)',
        rows,
    )
    conn.commit()
    conn.close()

    report, traces = run_script(region)
    assert report == {'region': region, 'clusters': expected_for(region)}
    assert 'qa-no-success' not in report['clusters']

    normalized = [
        {'sql': re.sub(r'\s+', ' ', item.get('sql', '')).strip(), 'params': item.get('params')}
        for item in traces
    ]

    pagination = []
    for item in normalized:
        upper = item['sql'].upper()
        values = flattened(item['params'])
        limit_five = bool(re.search(r'\bLIMIT\s+5\b', upper)) or (
            re.search(r'\bLIMIT\s+(?:\?|:\w+|\$\w+|@\w+)', item['sql'], re.IGNORECASE)
            and 5 in values
        )
        if (
            'BACKUPS' in upper and 'ORDER BY' in upper and 'TIMESTAMP' in upper
            and 'OFFSET' in upper and limit_five
        ):
            pagination.append(item)

    assert len(pagination) >= 2, (
        "The executed script must retrieve backup rows repeatedly in LIMIT 5/OFFSET pages"
    )

    aggregate = []
    for item in normalized:
        upper = item['sql'].upper()
        if 'BACKUPS' in upper and 'SUM' in upper and 'GROUP BY' in upper:
            aggregate.append(item)
    assert aggregate, "The executed script must run a separate SUM(...), GROUP BY aggregate query"
    assert all('LIMIT' not in item['sql'].upper() and 'OFFSET' not in item['sql'].upper()
               for item in aggregate), "The aggregate query must be separate from pagination"

    region_queries = [
        item for item in normalized
        if 'REGION' in item['sql'].upper()
        and has_placeholder(item['sql'])
        and region in flattened(item['params'])
    ]
    assert region_queries, "The executed region lookup must bind --region as a query parameter"

    status_queries = [
        item for item in normalized
        if 'STATUS' in item['sql'].upper()
        and has_placeholder(item['sql'])
        and 'SUCCESS' in flattened(item['params'])
    ]
    assert status_queries, "The executed status filter must bind SUCCESS as a query parameter"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
