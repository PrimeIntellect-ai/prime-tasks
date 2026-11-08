#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import shutil
import sqlite3
import subprocess
import tempfile
from collections import defaultdict, deque

import pytest

DB_PATH = '/home/user/company.db'
ANALYZER_DIR = '/home/user/analyzer'
MAIN_PATH = os.path.join(ANALYZER_DIR, 'main.go')
MODULE_PATH = os.path.join(ANALYZER_DIR, 'go.mod')
REPORT_PATH = os.path.join(ANALYZER_DIR, 'report.json')
BINARY_PATH = '/tmp/analyzer_submission'
EXPECTED_KEYS = {
    'cross_dept_traffic',
    'top_central_employees',
    'shortest_path_1_to_7',
}


def compute_expected():
    assert os.path.exists(DB_PATH), f'Database file {DB_PATH} does not exist.'
    conn = sqlite3.connect(DB_PATH)
    try:
        c = conn.cursor()

        c.execute('''
            SELECT d1.name, d2.name, c.bytes
            FROM communications c
            JOIN employees e1 ON c.sender_id = e1.id
            JOIN employees e2 ON c.receiver_id = e2.id
            JOIN departments d1 ON e1.department_id = d1.id
            JOIN departments d2 ON e2.department_id = d2.id
        ''')
        cross_dept_traffic = defaultdict(int)
        for d1, d2, bytes_transferred in c.fetchall():
            if d1 != d2:
                pair = f'{min(d1, d2)}-{max(d1, d2)}'
                cross_dept_traffic[pair] += bytes_transferred

        c.execute('SELECT sender_id, receiver_id FROM communications')
        graph = defaultdict(set)
        for u, v in c.fetchall():
            graph[u].add(v)
            graph[v].add(u)

        centrality = []
        for node, neighbors in graph.items():
            centrality.append((len(neighbors), -node, node))
        centrality.sort(key=lambda x: (x[0], x[1]), reverse=True)
        top_central_employees = [node for _, _, node in centrality[:3]]

        queue = deque([[1]])
        visited = {1}
        shortest_path = []
        while queue:
            path = queue.popleft()
            node = path[-1]
            if node == 7:
                shortest_path = path
                break
            for neighbor in sorted(graph[node]):
                if neighbor not in visited:
                    visited.add(neighbor)
                    queue.append(path + [neighbor])

        return {
            'cross_dept_traffic': dict(cross_dept_traffic),
            'top_central_employees': top_central_employees,
            'shortest_path_1_to_7': shortest_path,
        }
    finally:
        conn.close()


def build_program():
    assert os.path.isfile(MAIN_PATH), f'{MAIN_PATH} is missing or is not a file.'
    assert os.path.isfile(MODULE_PATH), f'{MODULE_PATH} is missing or is not a file.'
    result = subprocess.run(
        ['go', 'build', '-o', BINARY_PATH, '.'],
        cwd=ANALYZER_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert result.returncode == 0, f'Go application did not compile successfully:\n{result.stdout}'
    assert os.path.isfile(BINARY_PATH), 'Go build did not produce an executable.'


def run_program():
    if os.path.lexists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        [BINARY_PATH],
        cwd=ANALYZER_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, f'Go application exited unsuccessfully:\n{result.stdout}'
    assert os.path.exists(REPORT_PATH), f'Report file {REPORT_PATH} is missing.'
    assert os.path.isfile(REPORT_PATH), f'{REPORT_PATH} is not a file.'


def assert_report(expected):
    assert os.path.exists(REPORT_PATH), f'Report file {REPORT_PATH} is missing.'
    try:
        with open(REPORT_PATH, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f'File {REPORT_PATH} does not contain valid JSON: {exc}')

    assert isinstance(data, dict), 'The report must be a JSON object.'
    assert 'cross_dept_traffic' in data, "Missing 'cross_dept_traffic' in report."
    assert 'top_central_employees' in data, "Missing 'top_central_employees' in report."
    assert 'shortest_path_1_to_7' in data, "Missing 'shortest_path_1_to_7' in report."
    assert set(data) == EXPECTED_KEYS, f'Report has unexpected keys: {set(data) - EXPECTED_KEYS}'

    assert isinstance(data['cross_dept_traffic'], dict), 'cross_dept_traffic must be an object.'
    expected_traffic = expected['cross_dept_traffic']
    for pair, bytes_count in expected_traffic.items():
        assert pair in data['cross_dept_traffic'], f'Missing department pair {pair} in cross_dept_traffic.'
        assert data['cross_dept_traffic'][pair] == bytes_count, \
            f"Expected {bytes_count} bytes for {pair}, got {data['cross_dept_traffic'][pair]}."
    assert data['cross_dept_traffic'] == expected_traffic, \
        f"Expected exactly {expected_traffic}, got {data['cross_dept_traffic']}."

    assert data['top_central_employees'] == expected['top_central_employees'], \
        f"Expected top central employees {expected['top_central_employees']}, got {data['top_central_employees']}."
    assert data['shortest_path_1_to_7'] == expected['shortest_path_1_to_7'], \
        f"Expected shortest path {expected['shortest_path_1_to_7']}, got {data['shortest_path_1_to_7']}."


def install_alternate_communications():
    # This graph deliberately changes all three analytical results. Random byte
    # values ensure the report must be derived from the database used at runtime.
    edges = [
        (1, 2), (2, 7),
        (8, 1), (8, 2), (8, 3), (8, 4), (8, 5), (8, 6), (8, 9),
        (9, 1), (9, 2), (9, 3), (9, 4), (9, 5),
        (7, 3), (7, 4), (7, 5),
    ]
    rng = random.SystemRandom()
    rows = []
    for row_id, (sender, receiver) in enumerate(edges, 1):
        rows.append((row_id, sender, receiver, rng.randint(1001, 900000), '2026-01-01'))

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('DELETE FROM communications')
        conn.executemany(
            'INSERT INTO communications (id, sender_id, receiver_id, bytes, timestamp) VALUES (?, ?, ?, ?, ?)',
            rows,
        )
        conn.commit()
    finally:
        conn.close()


def restore_database(backup_path):
    for suffix in ('-wal', '-shm', '-journal'):
        sidecar = DB_PATH + suffix
        if os.path.exists(sidecar):
            os.remove(sidecar)
    shutil.copy2(backup_path, DB_PATH)


def test_compiled_go_pipeline_and_report():
    build_program()

    original_expected = compute_expected()
    run_program()
    assert_report(original_expected)

    fd, backup_path = tempfile.mkstemp(prefix='company-db-backup-', suffix='.db')
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)
    try:
        install_alternate_communications()
        alternate_expected = compute_expected()
        assert alternate_expected != original_expected
        run_program()
        assert_report(alternate_expected)
    finally:
        restore_database(backup_path)
        os.remove(backup_path)
        # Leave the required final artifact corresponding to the provided DB.
        run_program()

    assert_report(original_expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
