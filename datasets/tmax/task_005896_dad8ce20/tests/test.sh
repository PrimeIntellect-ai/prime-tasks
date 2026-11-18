#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/sqlite_instrument
cat << 'PY_EOF' > /tmp/sqlite_instrument/sitecustomize.py
import json
import os
import sqlite3

_real_connect = sqlite3.connect
_trace_path = os.environ.get('SQLITE_TRACE_FILE')

def _safe(value):
    if isinstance(value, dict):
        return {str(k): _safe(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [_safe(v) for v in value]
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    return repr(value)

def _log(conn_id, operation, sql, params=None):
    if not _trace_path:
        return
    event = {
        'connection': conn_id,
        'operation': operation,
        'sql': str(sql),
        'params': _safe(params),
    }
    with open(_trace_path, 'a', encoding='utf-8') as f:
        f.write(json.dumps(event) + '\n')

class CursorProxy:
    def __init__(self, cursor, conn_id):
        self._cursor = cursor
        self._conn_id = conn_id

    def execute(self, sql, parameters=()):
        _log(self._conn_id, 'execute', sql, parameters)
        self._cursor.execute(sql, parameters)
        return self

    def executemany(self, sql, seq_of_parameters):
        values = list(seq_of_parameters)
        _log(self._conn_id, 'executemany', sql, values)
        self._cursor.executemany(sql, values)
        return self

    def executescript(self, sql_script):
        _log(self._conn_id, 'executescript', sql_script, None)
        self._cursor.executescript(sql_script)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __next__(self):
        return next(self._cursor)

    def __enter__(self):
        self._cursor.__enter__()
        return self

    def __exit__(self, *args):
        return self._cursor.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

class ConnectionProxy:
    def __init__(self, connection):
        object.__setattr__(self, '_connection', connection)
        object.__setattr__(self, '_conn_id', id(connection))

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs), self._conn_id)

    def execute(self, sql, parameters=()):
        _log(self._conn_id, 'execute', sql, parameters)
        return CursorProxy(self._connection.execute(sql, parameters), self._conn_id)

    def executemany(self, sql, seq_of_parameters):
        values = list(seq_of_parameters)
        _log(self._conn_id, 'executemany', sql, values)
        return CursorProxy(self._connection.executemany(sql, values), self._conn_id)

    def executescript(self, sql_script):
        _log(self._conn_id, 'executescript', sql_script, None)
        return CursorProxy(self._connection.executescript(sql_script), self._conn_id)

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)

    def __setattr__(self, name, value):
        if name in ('_connection', '_conn_id'):
            object.__setattr__(self, name, value)
        else:
            setattr(self._connection, name, value)

def connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = connect
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

import pytest

SCRIPT = '/home/user/generate_report.py'
REPORT = '/home/user/report.json'
PRIMARY = '/home/user/db_backups/primary_metrics.db'
TOPOLOGY = '/home/user/db_backups/topology.db'
INSTRUMENT_DIR = '/tmp/sqlite_instrument'


def test_01_report_json_exists_and_correct():
    """Keep the original assertion for the requested manual invocation."""
    assert os.path.isfile(REPORT), f"Output file {REPORT} does not exist. Did you run your script?"

    with open(REPORT, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT} does not contain valid JSON.")

    expected_data = [
        {
            'host_id': 101,
            'host_name': 'db-node-01',
            'total_success_mb': 4500
        },
        {
            'host_id': 104,
            'host_name': 'db-node-04',
            'total_success_mb': 8000
        }
    ]

    assert isinstance(data, list), 'The JSON output should be a list of objects.'
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items in the report, but found {len(data)}."

    data_sorted = sorted(data, key=lambda x: x.get('host_id', 0))
    expected_sorted = sorted(expected_data, key=lambda x: x['host_id'])

    for i, (actual, expected) in enumerate(zip(data_sorted, expected_sorted)):
        assert actual.get('host_id') == expected['host_id'], f"Item {i}: expected host_id {expected['host_id']}, got {actual.get('host_id')}"
        assert actual.get('host_name') == expected['host_name'], f"Item {i}: expected host_name '{expected['host_name']}', got '{actual.get('host_name')}'"
        assert actual.get('total_success_mb') == expected['total_success_mb'], f"Item {i}: expected total_success_mb {expected['total_success_mb']}, got {actual.get('total_success_mb')}"


def test_02_script_exists():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."


def expected_report(region, bad_state, min_downstream):
    with sqlite3.connect(PRIMARY) as conn:
        hosts = conn.execute(
            'SELECT host_id, host_name FROM hosts WHERE region = ?', (region,)
        ).fetchall()
        bad_hosts = {
            row[0] for row in conn.execute(
                'SELECT DISTINCT host_id FROM backups WHERE state = ?', (bad_state,)
            )
        }
        success_totals = dict(conn.execute(
            "SELECT host_id, COALESCE(SUM(size_mb), 0) FROM backups "
            "WHERE state = 'SUCCESS' GROUP BY host_id"
        ).fetchall())

    with sqlite3.connect(TOPOLOGY) as conn:
        downstream = dict(conn.execute(
            'SELECT src_id, COUNT(DISTINCT dst_id) FROM replication_edges GROUP BY src_id'
        ).fetchall())

    result = []
    for host_id, host_name in hosts:
        if host_id in bad_hosts and downstream.get(host_id, 0) >= min_downstream:
            result.append({
                'host_id': host_id,
                'host_name': host_name,
                'total_success_mb': success_totals.get(host_id, 0),
            })
    return sorted(result, key=lambda item: item['host_id'])


def flatten_params(value):
    if isinstance(value, dict):
        output = []
        for item in value.values():
            output.extend(flatten_params(item))
        return output
    if isinstance(value, list):
        output = []
        for item in value:
            output.extend(flatten_params(item))
        return output
    return [value]


def run_and_check(region, bad_state, min_downstream):
    trace = tempfile.NamedTemporaryFile(prefix='sqlite-trace-', delete=False)
    trace.close()
    try:
        env = os.environ.copy()
        old_pythonpath = env.get('PYTHONPATH')
        env['PYTHONPATH'] = INSTRUMENT_DIR + (os.pathsep + old_pythonpath if old_pythonpath else '')
        env['SQLITE_TRACE_FILE'] = trace.name
        proc = subprocess.run(
            [
                'python3', SCRIPT,
                '--region', region,
                '--bad-state', bad_state,
                '--min-downstream', str(min_downstream),
            ],
            cwd='/home/user', env=env, text=True, capture_output=True, timeout=20,
        )
        assert proc.returncode == 0, (
            f"Script failed for region={region!r}, bad-state={bad_state!r}, "
            f"min-downstream={min_downstream}:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
        )
        assert os.path.isfile(REPORT), 'The script did not create /home/user/report.json.'
        with open(REPORT, encoding='utf-8') as f:
            actual = json.load(f)
        expected = expected_report(region, bad_state, min_downstream)
        assert actual == expected, f'Expected {expected!r}, got {actual!r}'
        for item in actual:
            assert isinstance(item, dict)
            assert set(item) == {'host_id', 'host_name', 'total_success_mb'}

        events = []
        with open(trace.name, encoding='utf-8') as f:
            for line in f:
                if line.strip():
                    events.append(json.loads(line))

        attach_events = [e for e in events if 'attach database' in e['sql'].lower()]
        assert attach_events, 'The script did not execute SQLite ATTACH DATABASE.'

        cross_queries = []
        for event in events:
            sql = event['sql'].lower()
            if ('replication_edges' in sql and 'hosts' in sql and 'backups' in sql
                    and ('select' in sql or 'with' in sql)):
                cross_queries.append(event)
        assert cross_queries, 'No single SQL query cross-queried hosts, backups, and replication_edges.'

        valid = False
        for query in cross_queries:
            values = flatten_params(query.get('params'))
            string_values = {str(v) for v in values}
            same_connection_attach = any(
                event['connection'] == query['connection'] for event in attach_events
            )
            if (same_connection_attach and region in string_values
                    and bad_state in string_values and str(min_downstream) in string_values):
                valid = True
                break
        assert valid, (
            'The cross-database query must run on the connection that performed ATTACH '
            'and must receive --region, --bad-state, and --min-downstream as SQL parameters.'
        )
    finally:
        try:
            os.unlink(trace.name)
        except FileNotFoundError:
            pass


def test_03_script_executes_parameterized_attached_cross_query():
    tempdir = tempfile.mkdtemp(prefix='db-verifier-')
    primary_copy = os.path.join(tempdir, 'primary_metrics.db')
    topology_copy = os.path.join(tempdir, 'topology.db')
    shutil.copy2(PRIMARY, primary_copy)
    shutil.copy2(TOPOLOGY, topology_copy)
    report_bytes = None
    if os.path.exists(REPORT):
        with open(REPORT, 'rb') as f:
            report_bytes = f.read()

    try:
        run_and_check('EU-Central', 'CORRUPT', 2)
        run_and_check('US-East', 'CORRUPT', 1)
        run_and_check('EU-Central', 'CORRUPT', 3)
        run_and_check('EU-Central', 'DOES-NOT-EXIST', 1)

        token = uuid.uuid4().hex[:10]
        hidden_region = 'Hidden-' + token
        hidden_state = 'BAD-' + token
        with sqlite3.connect(PRIMARY) as conn:
            next_host = conn.execute('SELECT COALESCE(MAX(host_id), 0) + 100 FROM hosts').fetchone()[0]
            next_backup = conn.execute('SELECT COALESCE(MAX(backup_id), 0) + 100 FROM backups').fetchone()[0]
            conn.executemany('INSERT INTO hosts VALUES (?, ?, ?)', [
                (next_host, 'hidden-source-' + token, hidden_region),
                (next_host + 1, 'hidden-decoy-' + token, hidden_region),
            ])
            conn.executemany('INSERT INTO backups VALUES (?, ?, ?, ?)', [
                (next_backup, next_host, hidden_state, 9),
                (next_backup + 1, next_host, 'SUCCESS', 123),
                (next_backup + 2, next_host, 'SUCCESS', 77),
                (next_backup + 3, next_host + 1, hidden_state, 4),
                (next_backup + 4, next_host + 1, 'SUCCESS', 999),
            ])
        with sqlite3.connect(TOPOLOGY) as conn:
            conn.executemany('INSERT INTO replication_edges VALUES (?, ?)', [
                (next_host, 101),
                (next_host, 101),
                (next_host, 102),
                (next_host + 1, 101),
                (next_host + 1, 101),
            ])

        run_and_check(hidden_region, hidden_state, 2)
    finally:
        shutil.copy2(primary_copy, PRIMARY)
        shutil.copy2(topology_copy, TOPOLOGY)
        if report_bytes is not None:
            with open(REPORT, 'wb') as f:
                f.write(report_bytes)
        elif os.path.exists(REPORT):
            os.unlink(REPORT)
        shutil.rmtree(tempdir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
