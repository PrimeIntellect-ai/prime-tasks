#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import io
import math
import os
import secrets
import sqlite3
import subprocess
import tempfile
from collections import Counter, defaultdict

DB = '/home/user/backup_meta.db'
SCRIPT = '/home/user/report.py'
REPORT = '/home/user/report_output.csv'
HEADER = ['cluster_name', 'backup_id', 'size_bytes', 'rolling_avg_size']

EXPECTED_CLUSTERS = [(1, 'us-east-cluster'), (2, 'eu-west-cluster')]
EXPECTED_NODES = [(10, 1, 'node-e1'), (20, 2, 'node-w1')]
EXPECTED_BACKUPS = [
    (100, 10, 'FULL', None, 5000, 'SUCCESS', '2023-10-01 10:00:00'),
    (101, 10, 'INC', 100, 500, 'SUCCESS', '2023-10-02 10:00:00'),
    (102, 10, 'INC', 101, 200, 'SUCCESS', '2023-10-03 10:00:00'),
    (103, 10, 'INC', 102, 100, 'FAILED', '2023-10-04 10:00:00'),
    (200, 20, 'FULL', None, 8000, 'SUCCESS', '2023-10-01 11:00:00'),
    (201, 20, 'INC', 200, 1000, 'SUCCESS', '2023-10-02 11:00:00'),
    (202, 20, 'INC', 201, 800, 'SUCCESS', '2023-10-03 11:00:00'),
    (203, 20, 'INC', 202, 600, 'SUCCESS', '2023-10-04 11:00:00'),
    (204, 20, 'INC', 203, 300, 'SUCCESS', '2023-10-05 11:00:00'),
]
EXPECTED_REPORT = [
    ('us-east-cluster', '100', '5000', 5000.00),
    ('us-east-cluster', '101', '500', 2750.00),
    ('us-east-cluster', '102', '200', 1900.00),
    ('eu-west-cluster', '200', '8000', 8000.00),
    ('eu-west-cluster', '201', '1000', 4500.00),
    ('eu-west-cluster', '202', '800', 3266.67),
    ('eu-west-cluster', '203', '600', 800.00),
    ('eu-west-cluster', '204', '300', 566.67),
]


def assert_original_data():
    assert os.path.isfile(DB) and not os.path.islink(DB), f'{DB} must be a regular database file.'
    conn = sqlite3.connect(DB)
    try:
        clusters = conn.execute('SELECT id, name FROM clusters ORDER BY id').fetchall()
        nodes = conn.execute('SELECT id, cluster_id, node_name FROM storage_nodes ORDER BY id').fetchall()
        backups = conn.execute('''
            SELECT id, storage_node_id, backup_type, parent_backup_id,
                   size_bytes, status, timestamp
            FROM backups ORDER BY id
        ''').fetchall()
    finally:
        conn.close()
    assert clusters == EXPECTED_CLUSTERS, 'The original cluster data was altered.'
    assert nodes == EXPECTED_NODES, 'The original storage-node data was altered.'
    assert backups == EXPECTED_BACKUPS, 'The original backup data was altered.'


def parse_report(text, label):
    try:
        rows = list(csv.reader(io.StringIO(text)))
    except Exception as exc:
        raise AssertionError(f'{label} is not valid CSV: {exc}')
    assert rows, f'{label} is empty.'
    assert rows[0] == HEADER, f'Expected header {HEADER}, got {rows[0]} in {label}.'

    parsed = []
    for row in rows[1:]:
        assert len(row) == 4, f'Row {row} in {label} does not have exactly 4 columns.'
        cluster, backup_id, size_bytes, avg_text = row
        try:
            avg = float(avg_text)
        except ValueError:
            raise AssertionError(f'Invalid rolling average {avg_text!r} in {label}.')
        assert math.isfinite(avg), f'Non-finite rolling average in {label}.'
        parsed.append((cluster, backup_id, size_bytes, round(avg, 2)))
    return parsed


def assert_report_matches(text, expected, label):
    actual = parse_report(text, label)
    normalized_expected = [(c, str(i), str(s), round(float(a), 2)) for c, i, s, a in expected]
    assert Counter(actual) == Counter(normalized_expected), (
        f'{label} does not match the expected report.\n'
        f'Expected: {normalized_expected}\nActual: {actual}'
    )


def run_report():
    result = subprocess.run(
        ['python3', SCRIPT], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert result.returncode == 0, f'report.py failed:\n{result.stderr}'
    return result.stdout


def create_dynamic_database(path):
    token = secrets.token_hex(5)
    a_name = 'dynamic-a-' + token
    b_name = 'dynamic-b-' + token
    base = 10000 + secrets.randbelow(100000)
    sizes = [secrets.randbelow(8000) + 101 for _ in range(8)]

    conn = sqlite3.connect(path)
    try:
        conn.executescript('''
            CREATE TABLE clusters (id INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE storage_nodes (
                id INTEGER PRIMARY KEY, cluster_id INTEGER, node_name TEXT,
                FOREIGN KEY(cluster_id) REFERENCES clusters(id));
            CREATE TABLE backups (
                id INTEGER PRIMARY KEY, storage_node_id INTEGER,
                backup_type TEXT, parent_backup_id INTEGER, size_bytes INTEGER,
                status TEXT, timestamp DATETIME,
                FOREIGN KEY(storage_node_id) REFERENCES storage_nodes(id));
        ''')
        conn.executemany('INSERT INTO clusters VALUES (?, ?)', [(1, a_name), (2, b_name)])
        conn.executemany('INSERT INTO storage_nodes VALUES (?, ?, ?)', [
            (10, 1, 'a-one'), (11, 1, 'a-two'), (20, 2, 'b-one')])
        records = [
            (base,   10, 'FULL', None,   sizes[0], 'SUCCESS', '2025-01-01 01:00:00'),
            (base+1, 10, 'INC',  base,   9999999,  'FAILED',  '2025-01-02 01:00:00'),
            (base+2, 11, 'INC',  base,   sizes[1], 'SUCCESS', '2025-01-03 01:00:00'),
            (base+3, 10, 'INC',  base+2, sizes[2], 'SUCCESS', '2025-01-04 01:00:00'),
            (base+4, 11, 'INC',  base+3, sizes[3], 'SUCCESS', '2025-01-05 01:00:00'),
            (base+5, 20, 'FULL', None,   sizes[4], 'SUCCESS', '2025-02-01 01:00:00'),
            (base+6, 20, 'INC',  base+5, sizes[5], 'SUCCESS', '2025-02-02 01:00:00'),
            (base+7, 20, 'INC',  base+6, sizes[6], 'SUCCESS', '2025-02-03 01:00:00'),
            (base+8, 20, 'INC',  base+7, sizes[7], 'SUCCESS', '2025-02-04 01:00:00'),
        ]
        conn.executemany('INSERT INTO backups VALUES (?, ?, ?, ?, ?, ?, ?)', records)
        conn.commit()
    finally:
        conn.close()

    successful = defaultdict(list)
    node_cluster = {10: a_name, 11: a_name, 20: b_name}
    for backup_id, node, _, _, size, status, timestamp in records:
        if status == 'SUCCESS':
            successful[node_cluster[node]].append((timestamp, backup_id, size))

    expected = []
    for cluster, items in successful.items():
        items.sort()
        prior_sizes = []
        for _, backup_id, size in items:
            prior_sizes.append(size)
            window = prior_sizes[-3:]
            expected.append((cluster, backup_id, size, round(sum(window) / len(window), 2)))
    return expected


def test_longest_chain():
    chain_file = '/home/user/longest_chain.txt'
    assert os.path.exists(chain_file), f'File {chain_file} is missing.'
    assert os.path.isfile(chain_file), f'{chain_file} is not a regular file.'
    with open(chain_file, 'r') as f:
        content = f.read().strip()
    assert content.isdigit(), f'Content of {chain_file} is not an integer: {content}'
    assert int(content) == 5, f'Expected longest chain to be 5, but got {content}.'


def test_index_exists_and_is_composite():
    assert_original_data()
    conn = sqlite3.connect(DB)
    try:
        row = conn.execute("SELECT tbl_name FROM sqlite_master WHERE type='index' AND name='idx_backup_perf'").fetchone()
        assert row is not None, "Index 'idx_backup_perf' was not found in the database."
        assert row[0] == 'backups', f"Index 'idx_backup_perf' should be on table 'backups', but is on '{row[0]}'."
        columns = [r[2] for r in conn.execute("PRAGMA index_info('idx_backup_perf')").fetchall()]
    finally:
        conn.close()
    assert len(columns) >= 2, "Index 'idx_backup_perf' must be composite."
    assert 'storage_node_id' in columns and 'status' in columns, (
        "Index 'idx_backup_perf' must include both storage_node_id and status."
    )


def test_report_script_output_and_dynamic_behavior():
    assert_original_data()
    assert os.path.isfile(SCRIPT) and not os.path.islink(SCRIPT), f'{SCRIPT} must be a regular Python file.'

    with open(SCRIPT, 'r') as f:
        source = f.read()
    try:
        tree = ast.parse(source, SCRIPT)
    except SyntaxError as exc:
        raise AssertionError(f'report.py is not valid Python: {exc}')
    strings = [n.value.upper() for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str)]
    required = ['SELECT', 'AVG', 'OVER', 'PARTITION BY', 'ORDER BY', 'ROWS BETWEEN',
                'JOIN', 'STORAGE_NODES', 'CLUSTERS', 'STATUS', 'SUCCESS']
    assert any(all(term in value for term in required) for value in strings), (
        'report.py must contain the joined SQL query with the required AVG window function and SUCCESS filter.'
    )

    assert os.path.isfile(REPORT), f'Report file {REPORT} is missing.'
    with open(REPORT, 'r', newline='') as f:
        stored_output = f.read()
    assert_report_matches(stored_output, EXPECTED_REPORT, REPORT)

    fresh_output = run_report()
    assert_report_matches(fresh_output, EXPECTED_REPORT, 'fresh report.py output')
    assert parse_report(fresh_output, 'fresh report.py output') == parse_report(stored_output, REPORT), (
        'Saved report_output.csv is not the output produced by the current report.py.'
    )
    assert_original_data()

    fd, saved_db = tempfile.mkstemp(prefix='original_backup_meta_', suffix='.db', dir='/tmp')
    os.close(fd)
    os.unlink(saved_db)
    fd, dynamic_db = tempfile.mkstemp(prefix='dynamic_backup_meta_', suffix='.db', dir='/tmp')
    os.close(fd)
    os.unlink(dynamic_db)

    try:
        create_expected = create_dynamic_database(dynamic_db)
        os.replace(DB, saved_db)
        os.replace(dynamic_db, DB)
        dynamic_output = run_report()
        assert_report_matches(dynamic_output, create_expected, 'report.py output on dynamic data')
    finally:
        if os.path.exists(DB):
            os.unlink(DB)
        if os.path.exists(saved_db):
            os.replace(saved_db, DB)
        if os.path.exists(dynamic_db):
            os.unlink(dynamic_db)

    assert_original_data()
    with open(REPORT, 'r', newline='') as f:
        assert f.read() == stored_output, 'Running report.py unexpectedly altered the saved report file.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
