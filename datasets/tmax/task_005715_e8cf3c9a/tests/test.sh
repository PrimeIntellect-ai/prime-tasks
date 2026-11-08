#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import heapq
import json
import os
import re
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile

import pytest

SCRIPT_PATH = '/home/user/report.py'
OUTPUT_PATH = '/home/user/report_output.txt'
DB_PATH = '/home/user/backups.db'


def format_output(totals, top_backups, shortest_path):
    lines = ['--- Total Size Per Region ---']
    lines.extend(f'{region}: {total} GB' for region, total in totals)
    lines.append('--- Top 2 Backups Per Region ---')
    lines.extend(
        f'{region} - {backup_id}: {size_gb} GB'
        for region, backup_id, size_gb in top_backups
    )
    lines.append('--- Shortest Path A to F ---')
    lines.append(f'Total Latency: {shortest_path} ms')
    return '\n'.join(lines) + '\n'


def expected_from_database():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()

    cur.execute('''
        SELECT n.region, SUM(b.size_gb)
        FROM nodes n
        JOIN backups b ON n.node_id = b.node_id
        GROUP BY n.region
        ORDER BY n.region
    ''')
    totals = cur.fetchall()

    cur.execute('''
        WITH Ranked AS (
            SELECT n.region, b.backup_id, b.size_gb,
                   ROW_NUMBER() OVER (
                       PARTITION BY n.region
                       ORDER BY b.size_gb DESC, b.backup_id ASC
                   ) AS rn
            FROM nodes n
            JOIN backups b ON n.node_id = b.node_id
        )
        SELECT region, backup_id, size_gb
        FROM Ranked
        WHERE rn <= 2
        ORDER BY region ASC, size_gb DESC, backup_id ASC
    ''')
    top_backups = cur.fetchall()

    cur.execute('''
        WITH RECURSIVE paths(target, total_latency) AS (
            SELECT target, latency_ms
            FROM network_links
            WHERE source = 'A'
            UNION ALL
            SELECT nl.target, p.total_latency + nl.latency_ms
            FROM paths p
            JOIN network_links nl ON p.target = nl.source
        )
        SELECT MIN(total_latency) FROM paths WHERE target = 'F'
    ''')
    shortest_path = cur.fetchone()[0]
    conn.close()
    return format_output(totals, top_backups, shortest_path)


def assert_output(expected):
    assert os.path.isfile(OUTPUT_PATH), (
        f'Expected output file not found at {OUTPUT_PATH}. Did the script run?'
    )
    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        actual = f.read().strip()

    expected_lines = expected.strip().splitlines()
    actual_lines = actual.splitlines()
    assert len(actual_lines) == len(expected_lines), (
        f'Output line count mismatch. Expected {len(expected_lines)} lines, '
        f'got {len(actual_lines)}.'
    )
    for i, (expected_line, actual_line) in enumerate(zip(expected_lines, actual_lines)):
        assert actual_line == expected_line, (
            f"Mismatch on line {i + 1}.\nExpected: '{expected_line}'\n"
            f"Actual:   '{actual_line}'"
        )


def run_report():
    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    trace_fd, trace_path = tempfile.mkstemp(prefix='report_sql_', suffix='.json')
    os.close(trace_fd)
    launcher_fd, launcher_path = tempfile.mkstemp(prefix='run_report_', suffix='.py')
    os.close(launcher_fd)
    with open(launcher_path, 'w', encoding='utf-8') as f:
        f.write('''
import json
import runpy
import sqlite3
import sys

trace = []
real_connect = sqlite3.connect

def traced_connect(*args, **kwargs):
    conn = real_connect(*args, **kwargs)
    conn.set_trace_callback(trace.append)
    return conn

sqlite3.connect = traced_connect
try:
    runpy.run_path('/home/user/report.py', run_name='__main__')
finally:
    with open(sys.argv[1], 'w', encoding='utf-8') as out:
        json.dump(trace, out)
''')

    try:
        result = subprocess.run(
            ['python3', launcher_path, trace_path],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f'report.py exited with status {result.returncode}.\n'
            f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
        )
        with open(trace_path, 'r', encoding='utf-8') as f:
            statements = json.load(f)
    finally:
        for path in (launcher_path, trace_path):
            if os.path.exists(path):
                os.remove(path)

    normalized = [' '.join(sql.upper().split()) for sql in statements]
    assert any('SUM(' in sql and re.search(r'\bJOIN\b', sql) for sql in normalized), (
        'report.py did not execute a joined SQL aggregate for regional totals.'
    )
    assert any(re.search(r'\bOVER\s*\(', sql) for sql in normalized), (
        'report.py did not execute a SQL window-function query.'
    )
    assert any(re.search(r'\bWITH\s+RECURSIVE\b', sql) for sql in normalized), (
        'report.py did not execute a recursive CTE.'
    )


def shortest_latency(edges):
    graph = {}
    for source, target, latency in edges:
        graph.setdefault(source, []).append((target, latency))
    queue = [(0, 'A')]
    best = {'A': 0}
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != best[node]:
            continue
        if node == 'F':
            return distance
        for target, weight in graph.get(node, []):
            candidate = distance + weight
            if candidate < best.get(target, float('inf')):
                best[target] = candidate
                heapq.heappush(queue, (candidate, target))
    raise AssertionError('Generated graph has no A-to-F path')


def install_random_database():
    token = secrets.token_hex(4)
    regions = [f'R-{token}-{suffix}' for suffix in ('Alpha', 'Beta', 'Gamma', 'Empty')]
    nodes = [
        ('A', regions[0]), ('N1', regions[0]),
        ('N2', regions[1]), ('N3', regions[1]),
        ('N4', regions[2]), ('F', regions[2]),
        ('UNUSED', regions[3]),
    ]

    base = secrets.randbelow(250) + 50
    assignments = [
        ('A', base), ('A', base), ('N1', secrets.randbelow(400) + 1),
        ('N1', secrets.randbelow(400) + 1),
        ('N2', secrets.randbelow(400) + 1), ('N2', secrets.randbelow(400) + 1),
        ('N3', secrets.randbelow(400) + 1),
        ('N4', secrets.randbelow(400) + 1),
        ('F', secrets.randbelow(400) + 1), ('F', secrets.randbelow(400) + 1),
    ]
    backups = [
        (f'bk-{secrets.token_hex(5)}', node, size)
        for node, size in assignments
    ]

    weight = lambda: secrets.randbelow(90) + 1
    edges = [
        ('A', 'N1', weight()), ('A', 'N2', weight()),
        ('A', 'N4', weight()), ('A', 'F', weight() + 120),
        ('N1', 'N3', weight()), ('N1', 'N4', weight()),
        ('N1', 'F', weight()), ('N2', 'N3', weight()),
        ('N2', 'F', weight()), ('N3', 'N4', weight()),
        ('N3', 'F', weight()), ('N4', 'F', weight()),
    ]

    for sidecar in (DB_PATH, DB_PATH + '-wal', DB_PATH + '-shm', DB_PATH + '-journal'):
        if os.path.exists(sidecar):
            os.remove(sidecar)
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.executescript('''
        CREATE TABLE nodes (node_id TEXT PRIMARY KEY, region TEXT);
        CREATE TABLE backups (backup_id TEXT PRIMARY KEY, node_id TEXT, size_gb INTEGER);
        CREATE TABLE network_links (source TEXT, target TEXT, latency_ms INTEGER);
    ''')
    cur.executemany('INSERT INTO nodes VALUES (?, ?)', nodes)
    cur.executemany('INSERT INTO backups VALUES (?, ?, ?)', backups)
    cur.executemany('INSERT INTO network_links VALUES (?, ?, ?)', edges)
    conn.commit()
    conn.close()

    node_regions = dict(nodes)
    totals_by_region = {}
    grouped = {}
    for backup_id, node_id, size in backups:
        region = node_regions[node_id]
        totals_by_region[region] = totals_by_region.get(region, 0) + size
        grouped.setdefault(region, []).append((backup_id, size))

    totals = sorted(totals_by_region.items())
    top = []
    for region in sorted(grouped):
        ranked = sorted(grouped[region], key=lambda item: (-item[1], item[0]))[:2]
        top.extend((region, backup_id, size) for backup_id, size in ranked)
    return format_output(totals, top, shortest_latency(edges))


def test_report_script_and_output():
    assert os.path.exists(SCRIPT_PATH), f'Missing required script: {SCRIPT_PATH}'
    mode = os.stat(SCRIPT_PATH, follow_symlinks=False).st_mode
    assert stat.S_ISREG(mode), 'report.py must be a regular Python file, not a symlink.'
    assert os.path.getsize(SCRIPT_PATH) > 0, 'report.py is empty.'
    assert os.path.isfile(DB_PATH), f'Database {DB_PATH} is missing.'

    temp_dir = tempfile.mkdtemp(prefix='report_verifier_')
    saved_db = os.path.join(temp_dir, 'backups.db')
    shutil.copy2(DB_PATH, saved_db)
    had_output = os.path.isfile(OUTPUT_PATH)
    saved_output = os.path.join(temp_dir, 'report_output.txt')
    if had_output:
        shutil.copy2(OUTPUT_PATH, saved_output)

    try:
        # Preserve the original verifier's exact check against the supplied database,
        # but generate the file by actually executing report.py.
        baseline_expected = expected_from_database()
        run_report()
        assert_output(baseline_expected)

        # Re-run the artifact on unpredictable databases so a fixed report cannot pass.
        for _ in range(3):
            expected = install_random_database()
            run_report()
            assert_output(expected)
    finally:
        for sidecar in (DB_PATH, DB_PATH + '-wal', DB_PATH + '-shm', DB_PATH + '-journal'):
            if os.path.exists(sidecar):
                os.remove(sidecar)
        shutil.copy2(saved_db, DB_PATH)
        if os.path.lexists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        if had_output:
            shutil.copy2(saved_output, OUTPUT_PATH)
        shutil.rmtree(temp_dir)
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
