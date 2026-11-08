#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

import pytest

SCRIPT = Path('/home/user/analyze_supply_chain.py')
OUTPUT = Path('/home/user/output.json')
NODES = Path('/home/user/data/components.csv')
EDGES = Path('/home/user/data/dependencies.csv')
LOADER = Path('/app/csv_graph_mapper/loader.py')

ORIGINAL_LOADER = '''import sqlite3
import concurrent.futures
import csv

class CSVGraphDB:
    def __init__(self, db_path=":memory:"):
        self.db_path = db_path
        self.conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self.conn.execute("PRAGMA journal_mode=WAL")
        self.conn.execute("CREATE TABLE IF NOT EXISTS nodes (id TEXT PRIMARY KEY, name TEXT, type TEXT)")
        self.conn.execute("CREATE TABLE IF NOT EXISTS edges (source TEXT, target TEXT)")
        self.conn.commit()

    def configure_index(self, column):
        self.conn.execute(f"CREATE INDEX IF NOT EXISTS idx_{column} ON nodes({column})")
        self.conn.commit()

    def load_nodes(self, csv_path):
        with open(csv_path, 'r') as f:
            reader = csv.reader(f)
            next(reader) # skip header
            self.conn.executemany("INSERT INTO nodes (id, name, type) VALUES (?, ?, ?)", reader)
            self.conn.commit()

    def load_edges_concurrently(self, csv_path, batch_size=1000):
        batches = []
        with open(csv_path, 'r') as f:
            reader = csv.reader(f)
            next(reader)
            batch = []
            for row in reader:
                batch.append(row)
                if len(batch) == batch_size:
                    batches.append(batch)
                    batch = []
            if batch:
                batches.append(batch)

        def worker(b):
            conn = sqlite3.connect(self.db_path, timeout=30)
            cursor = conn.cursor()
            for edge in b:
                cursor.execute("INSERT INTO edges (source, target) VALUES (?, ?)", edge)
                conn.commit() # PERTURBATION
            conn.close()

        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            executor.map(worker, batches)

    def query(self, sql):
        cursor = self.conn.cursor()
        cursor.execute(sql)
        return cursor.fetchall()
'''


def clear_runtime_databases():
    for root, _, files in os.walk('/home/user'):
        if root.startswith('/home/user/data'):
            continue
        for name in files:
            if name.endswith(('.db', '.sqlite', '.sqlite3', '-wal', '-shm')):
                try:
                    os.remove(os.path.join(root, name))
                except FileNotFoundError:
                    pass


def run_script(env=None, timeout=15):
    if OUTPUT.exists():
        OUTPUT.unlink()
    clear_runtime_databases()
    return subprocess.run(
        ['python3', str(SCRIPT)],
        capture_output=True,
        text=True,
        env=env,
        timeout=timeout,
    )


def read_output():
    assert OUTPUT.exists(), f'Output file not found at {OUTPUT}'
    try:
        with OUTPUT.open() as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'Failed to parse JSON from {OUTPUT}')


def write_graph(node_count, depth, dangling=False):
    with NODES.open('w', newline='') as f:
        f.write('id,name,type\n')
        for i in range(node_count):
            f.write(f'{i},DynamicComponent_{i},part\n')

    with EDGES.open('w', newline='') as f:
        f.write('source,target\n')
        for i in range(1, depth + 1):
            f.write(f'{i-1},{i}\n')
        for i in range(depth + 1, node_count):
            f.write(f'0,{i}\n')
        if dangling:
            f.write(f'0,{node_count + 1000}\n')


@pytest.fixture(scope='session', autouse=True)
def preserve_input_files():
    nodes_backup = NODES.read_bytes()
    edges_backup = EDGES.read_bytes()
    yield
    NODES.write_bytes(nodes_backup)
    EDGES.write_bytes(edges_backup)
    if OUTPUT.exists():
        OUTPUT.unlink()
    clear_runtime_databases()


def test_1_analyze_supply_chain_execution_and_output():
    assert SCRIPT.exists(), f'Script not found at {SCRIPT}'
    assert LOADER.exists(), f'Package source not found at {LOADER}'
    assert LOADER.read_text() != ORIGINAL_LOADER, 'The broken vendored loader was not modified'

    start = time.time()
    result = run_script()
    duration = time.time() - start

    assert result.returncode == 0, (
        f'Script failed with return code {result.returncode}.\n'
        f'Stdout: {result.stdout}\nStderr: {result.stderr}'
    )

    data = read_output()
    assert 'max_depth' in data, "Key 'max_depth' missing in output.json"
    assert 'total_nodes' in data, "Key 'total_nodes' missing in output.json"
    assert 'total_edges' in data, "Key 'total_edges' missing in output.json"
    assert data['max_depth'] == 14, f"Expected max_depth 14, got {data['max_depth']}"
    assert data['total_nodes'] == 50000, f"Expected 50000 nodes, got {data['total_nodes']}"
    assert data['total_edges'] == 49999, f"Expected 49999 edges, got {data['total_edges']}"
    assert duration <= 3.0, f'Execution time {duration:.2f}s exceeded threshold of 3.0s'


def test_2_dynamic_graph_uses_package_ingestion_and_recursive_query(tmp_path):
    write_graph(node_count=613, depth=23)

    hook_dir = tmp_path / 'hook'
    hook_dir.mkdir()
    log_path = tmp_path / 'calls.jsonl'
    (hook_dir / 'sitecustomize.py').write_text(r'''
import json
import os
try:
    import csv_graph_mapper
    cls = csv_graph_mapper.CSVGraphDB
    log_path = os.environ.get('CGM_CALL_LOG')

    def wrap(name):
        original = getattr(cls, name)
        def wrapped(self, *args, **kwargs):
            if log_path:
                record = {'method': name, 'args': [str(x) for x in args]}
                with open(log_path, 'a') as log:
                    log.write(json.dumps(record) + '\n')
            return original(self, *args, **kwargs)
        setattr(cls, name, wrapped)

    for method in ('configure_index', 'load_nodes', 'load_edges_concurrently', 'query'):
        if hasattr(cls, method):
            wrap(method)
except Exception:
    pass
''')

    env = os.environ.copy()
    env['PYTHONPATH'] = str(hook_dir) + os.pathsep + env.get('PYTHONPATH', '')
    env['CGM_CALL_LOG'] = str(log_path)
    result = run_script(env=env)
    assert result.returncode == 0, (
        f'Script failed on a derived graph.\nStdout: {result.stdout}\nStderr: {result.stderr}'
    )

    data = read_output()
    assert set(data) == {'max_depth', 'total_nodes', 'total_edges'}
    assert data == {'max_depth': 23, 'total_nodes': 613, 'total_edges': 612}

    assert log_path.exists(), 'No csv_graph_mapper operations were observed'
    calls = [json.loads(line) for line in log_path.read_text().splitlines() if line.strip()]
    methods = [call['method'] for call in calls]
    assert 'configure_index' in methods, 'The script did not configure an index through the package'
    assert any(
        call['method'] == 'configure_index' and call['args'] and call['args'][0] == 'part_id'
        for call in calls
    ), "The script did not configure the requested 'part_id' indexing strategy"
    assert any(
        call['method'] == 'load_nodes' and call['args'] and call['args'][0] == str(NODES)
        for call in calls
    ), 'The components CSV was not loaded through csv_graph_mapper'
    assert any(
        call['method'] == 'load_edges_concurrently' and call['args'] and call['args'][0] == str(EDGES)
        for call in calls
    ), 'The concurrent edge-ingestion interface was not used'

    query_text = '\n'.join(
        call['args'][0] for call in calls
        if call['method'] == 'query' and call['args']
    ).lower()
    assert 'with recursive' in query_text, 'No recursive CTE was issued through the query interface'
    assert 'nodes' in query_text and 'edges' in query_text, 'Queries did not inspect the ingested graph'
    assert 'count' in query_text, 'Graph counts were not queried for output validation'


def test_3_invalid_graph_is_rejected():
    write_graph(node_count=31, depth=7, dangling=True)
    result = run_script()
    assert result.returncode != 0 or not OUTPUT.exists(), (
        'The script wrote a successful result for a graph containing an edge to a missing node; '
        'graph structure was not validated'
    )


def test_4_repaired_package_ingests_and_queries_real_data(tmp_path):
    import sys
    sys.path.insert(0, '/app')
    from csv_graph_mapper import CSVGraphDB

    nodes = tmp_path / 'nodes.csv'
    edges = tmp_path / 'edges.csv'
    nodes.write_text(
        'id,name,type\n' + ''.join(f'{i},N{i},part\n' for i in range(180))
    )
    edges.write_text(
        'source,target\n'
        + ''.join(f'{i-1},{i}\n' for i in range(1, 12))
        + ''.join(f'0,{i}\n' for i in range(12, 180))
    )

    db_path = tmp_path / 'graph.sqlite'
    db = CSVGraphDB(str(db_path))
    db.configure_index('part_id')
    db.load_nodes(str(nodes))
    db.load_edges_concurrently(str(edges), batch_size=13)

    assert db.query('SELECT COUNT(*) FROM nodes')[0][0] == 180
    assert db.query('SELECT COUNT(*) FROM edges')[0][0] == 179

    columns = [row[1] for row in db.query('PRAGMA table_info(nodes)')]
    node_id = 'part_id' if 'part_id' in columns else 'id'
    recursive_sql = f'''WITH RECURSIVE walk(node, depth) AS (
        SELECT {node_id}, 0 FROM nodes
        WHERE {node_id} NOT IN (SELECT target FROM edges)
        UNION ALL
        SELECT e.target, walk.depth + 1
        FROM walk JOIN edges e ON e.source = walk.node
    ) SELECT MAX(depth) FROM walk'''
    assert db.query(recursive_sql)[0][0] == 11
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
