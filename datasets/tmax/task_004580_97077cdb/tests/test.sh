#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/run_pipeline_instrumented.py
import json
import runpy
import sqlite3

sql_statements = []
graphs_created = []

_real_connect = sqlite3.connect

class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, parameters=()):
        sql_statements.append(str(sql))
        self._cursor.execute(sql, parameters)
        return self

    def executemany(self, sql, seq_of_parameters):
        sql_statements.append(str(sql))
        self._cursor.executemany(sql, seq_of_parameters)
        return self

    def executescript(self, sql):
        sql_statements.append(str(sql))
        self._cursor.executescript(sql)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

class ConnectionProxy:
    def __init__(self, connection):
        self._connection = connection

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, parameters=()):
        sql_statements.append(str(sql))
        return CursorProxy(self._connection.execute(sql, parameters))

    def executemany(self, sql, seq_of_parameters):
        sql_statements.append(str(sql))
        return CursorProxy(self._connection.executemany(sql, seq_of_parameters))

    def executescript(self, sql):
        sql_statements.append(str(sql))
        return CursorProxy(self._connection.executescript(sql))

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)

def tracked_connect(*args, **kwargs):
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = tracked_connect

import networkx as nx
_real_digraph_init = nx.DiGraph.__init__

def tracked_digraph_init(self, *args, **kwargs):
    _real_digraph_init(self, *args, **kwargs)
    graphs_created.append(type(self).__name__)

nx.DiGraph.__init__ = tracked_digraph_init

result_path = '/tmp/pipeline_instrumentation.json'
try:
    runpy.run_path('/home/user/pipeline.py', run_name='__main__')
finally:
    with open(result_path, 'w') as f:
        json.dump({'sql': sql_statements, 'directed_graphs': graphs_created}, f)
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import re
import secrets
import sqlite3
import stat
import subprocess

DB_PATH = '/home/user/etl_source.db'
CSV_PATH = '/home/user/graph_in_degrees.csv'
PIPELINE_PATH = '/home/user/pipeline.py'


def read_csv():
    with open(CSV_PATH, 'r', newline='') as f:
        return list(csv.reader(f))


def test_final_state_and_pipeline_behavior():
    # Preserve the original final-state assertions.
    assert os.path.exists(DB_PATH), f"Database file missing at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    index = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_stale_data';"
    ).fetchone()
    conn.close()
    assert index is None, "The inefficient index 'idx_stale_data' was not dropped from the database."

    assert os.path.exists(CSV_PATH), f"Output CSV file missing at {CSV_PATH}"
    expected_original = [
        ['node', 'in_degree'],
        ['A', '1'],
        ['B', '2'],
        ['C', '2'],
        ['D', '1']
    ]
    assert read_csv() == expected_original, "CSV content does not match expected output."

    # The requested artifact must be an actual, syntactically valid Python file.
    assert os.path.lexists(PIPELINE_PATH), f"Pipeline script missing at {PIPELINE_PATH}"
    assert not os.path.islink(PIPELINE_PATH), "pipeline.py must be a regular file, not a symlink"
    mode = os.stat(PIPELINE_PATH).st_mode
    assert stat.S_ISREG(mode), "pipeline.py is not a regular file"
    with open(PIPELINE_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    ast.parse(source, filename=PIPELINE_PATH)

    # Replace the events with verifier-generated data unknown to the submission.
    prefix = 'N' + secrets.token_hex(5)
    a, b, c, d, unused = [prefix + suffix for suffix in ('_a', '_b', '_c', '_d', '_unused')]
    events = [
        (101, a, b, '2042-03-01 01:00:00', 'SUCCESS'),
        (102, a, b, '2042-03-01 03:00:00', 'SUCCESS'),
        (103, a, b, '2042-03-01 04:00:00', 'FAILED'),
        (104, a, c, '2042-03-01 02:00:00', 'SUCCESS'),
        (105, b, c, '2042-03-01 01:00:00', 'SUCCESS'),
        (106, b, c, '2042-03-02 01:00:00', 'SUCCESS'),
        (107, c, a, '2042-03-03 01:00:00', 'FAILED'),
        (108, d, a, '2042-03-01 01:00:00', 'SUCCESS'),
        (109, d, b, '2042-03-01 01:00:00', 'SUCCESS'),
        (110, a, d, '2042-03-01 01:00:00', 'SUCCESS'),
        (111, unused, a, '2042-03-04 01:00:00', 'success'),
        (112, b, unused, '2042-03-04 02:00:00', 'SUCCESS '),
    ]

    conn = sqlite3.connect(DB_PATH)
    conn.execute('DELETE FROM events')
    conn.executemany(
        'INSERT INTO events (id, src_node, dst_node, event_time, status) VALUES (?, ?, ?, ?, ?)',
        events,
    )
    # Permit scripts which drop the index without IF EXISTS to be executed again.
    conn.execute('DROP INDEX IF EXISTS idx_stale_data')
    conn.execute('CREATE INDEX idx_stale_data ON events (status, event_time)')
    conn.commit()
    conn.close()

    # Independently derive the expected graph from the altered input.
    latest = {}
    for _, src, dst, event_time, status_value in events:
        if status_value == 'SUCCESS':
            key = (src, dst)
            if key not in latest or event_time > latest[key]:
                latest[key] = event_time
    nodes = {node for edge in latest for node in edge}
    degrees = {node: 0 for node in nodes}
    for src, dst in latest:
        degrees[dst] += 1
    expected_dynamic = [['node', 'in_degree']] + [
        [node, str(degrees[node])] for node in sorted(degrees)
    ]

    if os.path.exists('/tmp/pipeline_instrumentation.json'):
        os.remove('/tmp/pipeline_instrumentation.json')
    result = subprocess.run(
        ['python3', '/tmp/run_pipeline_instrumented.py'],
        cwd='/home/user', text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, (
        f"pipeline.py did not execute successfully. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert os.path.exists(CSV_PATH), "pipeline.py did not generate graph_in_degrees.csv"
    assert read_csv() == expected_dynamic, "Pipeline output is incorrect for altered event data"

    with open('/tmp/pipeline_instrumentation.json', 'r') as f:
        trace = json.load(f)

    # Require one extraction query over events, and require that query to use a
    # partitioned SQL window. Other metadata/DDL statements are not counted.
    extraction_queries = []
    for statement in trace.get('sql', []):
        normalized = ' '.join(statement.lower().split())
        if re.search(r'\b(select|with)\b', normalized) and re.search(r'\bevents\b', normalized):
            extraction_queries.append(normalized)
    assert len(extraction_queries) == 1, (
        f"Expected one SQL extraction query over events, got {len(extraction_queries)}"
    )
    query = extraction_queries[0]
    assert re.search(r'\bover\s*\(', query), "Extraction query does not use a window function"
    assert re.search(r'\bpartition\s+by\b', query), "Window query does not partition directed pairs"
    assert re.search(r'\bstatus\b', query), "Extraction query does not filter event status"

    assert trace.get('directed_graphs'), "pipeline.py did not materialize a NetworkX directed graph"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
