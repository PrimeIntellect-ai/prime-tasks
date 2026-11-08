#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import json
import os
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile
from collections import deque

import pytest

DB_PATH = '/home/user/network.db'
SOLUTION_PATH = '/home/user/solution.json'
BAD_REPORT_PATH = '/home/user/bad_report.py'


def get_truth_values():
    if not os.path.exists(DB_PATH):
        pytest.fail(f"Database file {DB_PATH} is missing, cannot compute truth.")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute('SELECT id, hostname FROM servers')
    servers = {row[0]: row[1] for row in cursor.fetchall()}
    server_ids = {v: k for k, v in servers.items()}

    start_hostname = 'Gateway-01'
    end_hostname = 'Database-Cluster'
    if start_hostname not in server_ids or end_hostname not in server_ids:
        conn.close()
        pytest.fail('Required servers are missing from the database.')

    start_id = server_ids[start_hostname]
    end_id = server_ids[end_hostname]

    cursor.execute('SELECT source_id, target_id FROM connections')
    adj = {}
    for u, v in cursor.fetchall():
        adj.setdefault(u, []).append(v)

    queue = deque([[start_id]])
    visited = {start_id}
    shortest_path_ids = None
    while queue:
        path = queue.popleft()
        node = path[-1]
        if node == end_id:
            shortest_path_ids = path
            break
        for neighbor in adj.get(node, []):
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append(path + [neighbor])

    if not shortest_path_ids:
        conn.close()
        pytest.fail('No path found between Gateway-01 and Database-Cluster.')

    shortest_path_hostnames = [servers[nid] for nid in shortest_path_ids]
    total_traffic = 0
    for u, v in zip(shortest_path_ids, shortest_path_ids[1:]):
        cursor.execute(
            'SELECT SUM(bytes_transferred) FROM traffic_logs '
            'WHERE conn_source = ? AND conn_target = ?',
            (u, v),
        )
        result = cursor.fetchone()[0]
        if result is not None:
            total_traffic += result

    conn.close()
    return shortest_path_hostnames, total_traffic


def read_solution():
    assert os.path.exists(SOLUTION_PATH), f'The solution file {SOLUTION_PATH} does not exist.'
    with open(SOLUTION_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'The file {SOLUTION_PATH} does not contain valid JSON.')


def test_solution_json_exists_and_valid():
    data = read_solution()
    assert isinstance(data, dict), 'The JSON file should contain a dictionary object.'
    assert 'shortest_path' in data, "The JSON file is missing the 'shortest_path' key."
    assert 'total_traffic' in data, "The JSON file is missing the 'total_traffic' key."


def test_solution_values():
    data = read_solution()
    expected_path, expected_traffic = get_truth_values()
    actual_path = data.get('shortest_path')
    actual_traffic = data.get('total_traffic')

    assert actual_path == expected_path, \
        f'Incorrect shortest path. Expected {expected_path}, but got {actual_path}.'
    assert actual_traffic == expected_traffic, \
        f'Incorrect total traffic. Expected {expected_traffic}, but got {actual_traffic}.'


def resolve_string(node, constants):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return constants.get(node.id)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = resolve_string(node.left, constants)
        right = resolve_string(node.right, constants)
        if left is not None and right is not None:
            return left + right
    return None


def uses_parameterized_traffic_query(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            tree = ast.parse(f.read(), filename=path)
    except (OSError, UnicodeError, SyntaxError):
        return False

    constants = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            value = resolve_string(node.value, constants)
            if value is not None:
                constants[node.targets[0].id] = value

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr != 'execute' or not node.args:
            continue
        sql = resolve_string(node.args[0], constants)
        if sql is None:
            continue
        normalized = ' '.join(sql.lower().split())
        has_parameters = len(node.args) >= 2 or any(
            kw.arg in ('parameters', 'params') for kw in node.keywords
        )
        if (
            'select' in normalized
            and 'sum' in normalized
            and 'bytes_transferred' in normalized
            and 'traffic_logs' in normalized
            and 'conn_source' in normalized
            and 'conn_target' in normalized
            and normalized.count('?') >= 2
            and has_parameters
        ):
            return True
    return False


def run_script_and_check(script, expected_path, expected_traffic):
    if os.path.lexists(SOLUTION_PATH):
        os.remove(SOLUTION_PATH)
    try:
        result = subprocess.run(
            ['python3', script],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False

    if result.returncode != 0 or not os.path.isfile(SOLUTION_PATH):
        return False
    try:
        with open(SOLUTION_PATH, 'r') as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return False
    return (
        isinstance(data, dict)
        and data.get('shortest_path') == expected_path
        and data.get('total_traffic') == expected_traffic
    )


def test_optimized_python_script_exists_and_is_dynamic():
    candidates = []
    for path in glob.glob('/home/user/**/*.py', recursive=True):
        if os.path.abspath(path) == BAD_REPORT_PATH or os.path.islink(path):
            continue
        try:
            if stat.S_ISREG(os.stat(path).st_mode) and uses_parameterized_traffic_query(path):
                candidates.append(path)
        except OSError:
            pass

    assert candidates, (
        'No agent-written Python script containing a parameterized SQL aggregation '
        'for the path edges was found.'
    )

    fd, backup_path = tempfile.mkstemp(prefix='network-backup-', suffix='.db')
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)
    passing_script = None

    try:
        original_path, original_traffic = get_truth_values()
        for script in candidates:
            shutil.copy2(backup_path, DB_PATH)
            if not run_script_and_check(script, original_path, original_traffic):
                continue

            # Exercise the implementation on verifier-generated data. A new direct
            # route must become the shortest path, and both of its log rows must be summed.
            shutil.copy2(backup_path, DB_PATH)
            conn = sqlite3.connect(DB_PATH)
            cursor = conn.cursor()
            cursor.execute("SELECT id FROM servers WHERE hostname = ?", ('Gateway-01',))
            start_id = cursor.fetchone()[0]
            cursor.execute("SELECT id FROM servers WHERE hostname = ?", ('Database-Cluster',))
            end_id = cursor.fetchone()[0]
            first = 1000000 + secrets.randbelow(1000000)
            second = 2000000 + secrets.randbelow(1000000)
            cursor.execute(
                'INSERT INTO connections (source_id, target_id) VALUES (?, ?)',
                (start_id, end_id),
            )
            cursor.executemany(
                'INSERT INTO traffic_logs '
                '(conn_source, conn_target, bytes_transferred, timestamp) VALUES (?, ?, ?, ?)',
                [
                    (start_id, end_id, first, 'verifier-generated-1'),
                    (start_id, end_id, second, 'verifier-generated-2'),
                ],
            )
            conn.commit()
            conn.close()

            mutated_path, mutated_traffic = get_truth_values()
            if run_script_and_check(script, mutated_path, mutated_traffic):
                passing_script = script
                break

        assert passing_script is not None, (
            'No parameterized Python implementation successfully generated solution.json '
            'from both the supplied database and verifier-generated database contents.'
        )
    finally:
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)

    # Leave the required output corresponding to the original database in place.
    final_path, final_traffic = get_truth_values()
    assert run_script_and_check(passing_script, final_path, final_traffic), \
        'The optimized script did not regenerate the final solution for the original database.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
