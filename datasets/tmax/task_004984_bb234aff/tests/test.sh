#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import shutil
import sqlite3
import subprocess
import time

import pytest

SCRIPT = '/home/user/fast_verifier.py'
BINARY = '/app/chunk_verifier'
DB = '/home/user/backup_metadata.db'
BACKUP = '/tmp/backup_metadata.original.db'
WRAPPER = '/tmp/run_with_sql_trace.py'

WRAPPER_SOURCE = r'''
import json
import os
import runpy
import sqlite3
import sys

trace = []
_real_connect = sqlite3.connect
_MISSING = object()

def normalize(value):
    if isinstance(value, dict):
        return {str(k): normalize(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [normalize(v) for v in value]
    if value is None or isinstance(value, (str, int, float, bytes)):
        if isinstance(value, bytes):
            return {'__bytes__': list(value)}
        return value
    return {'__unsupported__': repr(value)}

class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, parameters=_MISSING):
        supplied = parameters is not _MISSING
        trace.append({
            'sql': sql if isinstance(sql, str) else repr(sql),
            'parameters_supplied': supplied,
            'parameters': normalize(parameters) if supplied else None,
        })
        if supplied:
            self._cursor.execute(sql, parameters)
        else:
            self._cursor.execute(sql)
        return self

    def executemany(self, sql, seq):
        return self._cursor.executemany(sql, seq)

    def executescript(self, sql):
        return self._cursor.executescript(sql)

    def fetchone(self):
        return self._cursor.fetchone()

    def fetchmany(self, *args, **kwargs):
        return self._cursor.fetchmany(*args, **kwargs)

    def fetchall(self):
        return self._cursor.fetchall()

    def __iter__(self):
        return iter(self._cursor)

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

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, parameters=_MISSING):
        cursor = CursorProxy(self._connection.cursor())
        return cursor.execute(sql, parameters) if parameters is not _MISSING else cursor.execute(sql)

    def executemany(self, sql, seq):
        return self._connection.executemany(sql, seq)

    def executescript(self, sql):
        return self._connection.executescript(sql)

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)

    def __setattr__(self, name, value):
        if name == '_connection':
            object.__setattr__(self, name, value)
        else:
            setattr(self._connection, name, value)

def traced_connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = traced_connect
sys.argv = [sys.argv[1]]
try:
    runpy.run_path(sys.argv[0], run_name='__main__')
finally:
    with open(os.environ['SQL_TRACE_FILE'], 'w') as f:
        json.dump(trace, f)
'''


def run(command, timeout):
    return subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=timeout, check=True)


def assert_integer_output(raw):
    assert re.fullmatch(rb'-?[0-9]+\n', raw), \
        f'Output must be exactly one integer followed by a newline; got {raw!r}'


def create_random_database(seed):
    rng = random.Random(seed)
    if os.path.exists(DB):
        os.remove(DB)
    conn = sqlite3.connect(DB)
    try:
        conn.execute('CREATE TABLE chunks (id INTEGER PRIMARY KEY, size INTEGER, timestamp DATETIME)')
        conn.execute('CREATE TABLE chunk_dependencies (parent_id INTEGER, child_id INTEGER)')

        chain_count = rng.randint(3, 8)
        lengths = [rng.randint(4, 18) for _ in range(chain_count)]
        ids = rng.sample(range(10, 500000), sum(lengths))
        offset = 0
        totals = []
        chunk_rows = []
        edge_rows = []
        for chain_number, length in enumerate(lengths):
            chain_ids = ids[offset:offset + length]
            offset += length
            total = 0
            for depth, chunk_id in enumerate(chain_ids):
                size = rng.randint(10, 100)
                total += size
                chunk_rows.append((chunk_id, size, f'2026-01-{(depth % 28) + 1:02d}T00:00:00'))
                if depth:
                    edge_rows.append((chain_ids[depth - 1], chunk_id))
            totals.append(total)

        rng.shuffle(chunk_rows)
        rng.shuffle(edge_rows)
        conn.executemany('INSERT INTO chunks(id, size, timestamp) VALUES (?, ?, ?)', chunk_rows)
        conn.executemany('INSERT INTO chunk_dependencies(parent_id, child_id) VALUES (?, ?)', edge_rows)
        conn.commit()
        return max(totals), chunk_rows, edge_rows
    finally:
        conn.close()


def decode_parameters(value):
    if isinstance(value, dict):
        if '__bytes__' in value:
            return bytes(value['__bytes__'])
        assert '__unsupported__' not in value, f'Unsupported SQL parameter: {value}'
        return {k: decode_parameters(v) for k, v in value.items()}
    if isinstance(value, list):
        return tuple(decode_parameters(v) for v in value)
    return value


def qualifying_query(entry):
    sql = entry.get('sql', '')
    return (entry.get('parameters_supplied') and
            re.search(r'\bWITH\b', sql, re.I) and
            re.search(r'\bOVER\s*\(', sql, re.I) and
            re.search(r'(\?|[:@$][A-Za-z_][A-Za-z0-9_]*)', sql))


def verify_sql_result(trace, expected):
    candidates = [entry for entry in trace if qualifying_query(entry)]
    assert candidates, ('The executed computation must be a parameterized SQL query '
                        'using a CTE and a window function (OVER (...)).')

    errors = []
    for entry in candidates:
        try:
            params = decode_parameters(entry['parameters'])
            conn = sqlite3.connect(DB)
            try:
                rows = conn.execute(entry['sql'], params).fetchall()
            finally:
                conn.close()
            if rows == [(expected,)]:
                return
            errors.append(f'query returned {rows!r}')
        except Exception as exc:
            errors.append(str(exc))
    pytest.fail('No executed CTE/window query independently produced the required single integer: '
                + '; '.join(errors))


def test_fast_verifier_speedup_and_general_computation():
    assert os.path.exists(SCRIPT), f'Agent script missing at {SCRIPT}'
    assert os.path.isfile(SCRIPT), f'Agent script is not a regular file: {SCRIPT}'
    assert os.path.exists(BINARY), f'Binary missing at {BINARY}'
    assert os.path.exists(DB), f'Database missing at {DB}'

    shutil.copy2(DB, BACKUP)
    with open(WRAPPER, 'w') as f:
        f.write(WRAPPER_SOURCE)

    try:
        start_binary = time.monotonic()
        binary = run([BINARY, DB], timeout=10)
        binary_time = time.monotonic() - start_binary

        start_agent = time.monotonic()
        agent = run(['python3', SCRIPT], timeout=5)
        agent_time = time.monotonic() - start_agent

        assert_integer_output(agent.stdout)
        assert binary.stdout.decode().strip() == agent.stdout.decode().strip(), \
            f"Output mismatch: binary output {binary.stdout!r} != agent output {agent.stdout!r}"
        speedup = binary_time / agent_time
        assert speedup >= 5.0, \
            f'Speedup too low: {speedup:.2f}x (needs >= 5.0x). Binary time: {binary_time:.4f}s, Agent time: {agent_time:.4f}s'

        for case in range(3):
            seed = secrets.randbits(64)
            expected, chunk_rows, edge_rows = create_random_database(seed)
            trace_path = f'/tmp/sql_trace_{case}.json'
            env = os.environ.copy()
            env['SQL_TRACE_FILE'] = trace_path
            result = subprocess.run(['python3', WRAPPER, SCRIPT], env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    timeout=1.5, check=True)
            assert_integer_output(result.stdout)
            assert int(result.stdout) == expected, \
                f'Incorrect result on generated database (seed {seed})'
            assert os.path.exists(trace_path), 'SQL execution trace was not produced'
            with open(trace_path) as f:
                trace = json.load(f)

            # Restore the generated fixture before independently exercising the submitted query.
            recreated, _, _ = create_random_database(seed)
            assert recreated == expected
            verify_sql_result(trace, expected)
    finally:
        if os.path.exists(BACKUP):
            shutil.copy2(BACKUP, DB)

PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
