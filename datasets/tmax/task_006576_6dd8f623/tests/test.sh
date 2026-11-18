#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import collections
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys

DB_PATH = Path('/home/user/research_data.db')
RESULT_PATH = Path('/home/user/path_result.json')
BACKUP_PATH = Path('/tmp/research_data_original.db')
EXPECTED_ORIGINAL_PATH = [
    'Dr. Alan Grant',
    'Dr. Ian Malcolm',
    'Dr. Henry Wu',
    'Dr. Ellie Sattler',
]


def load_result():
    assert RESULT_PATH.exists(), f'Expected result file {RESULT_PATH} is missing.'
    assert RESULT_PATH.is_file(), f'{RESULT_PATH} is not a regular file.'
    try:
        with RESULT_PATH.open('r') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File {RESULT_PATH} does not contain valid JSON.') from exc

    assert 'path' in data, "The JSON object is missing the required 'path' key."
    assert 'distance' in data, "The JSON object is missing the required 'distance' key."
    assert set(data.keys()) == {'path', 'distance'}, \
        f"The JSON object contains unexpected keys: {set(data.keys()) - {'path', 'distance'}}"
    assert isinstance(data['path'], list), "'path' must be an array."
    assert isinstance(data['distance'], int), "'distance' must be an integer."
    return data


def assert_original_result():
    data = load_result()
    assert data['path'] == EXPECTED_ORIGINAL_PATH, \
        f"Expected path {EXPECTED_ORIGINAL_PATH}, but got {data['path']}."
    assert data['distance'] == 3, \
        f"Expected distance 3, but got {data['distance']}."


def sqlite_backup(source, destination):
    if destination.exists():
        destination.unlink()
    with sqlite3.connect(source) as src, sqlite3.connect(destination) as dst:
        src.backup(dst)


def restore_database():
    for suffix in ('', '-wal', '-shm'):
        try:
            Path(str(DB_PATH) + suffix).unlink()
        except FileNotFoundError:
            pass
    with sqlite3.connect(BACKUP_PATH) as src, sqlite3.connect(DB_PATH) as dst:
        src.backup(dst)


def expected_from_database():
    graph = collections.defaultdict(set)
    with sqlite3.connect(DB_PATH) as con:
        rows = con.execute('''
            SELECT r1.name, r2.name
            FROM publication p
            JOIN authorship a1 ON a1.pub_id = p.id
            JOIN authorship a2 ON a2.pub_id = p.id AND a1.researcher_id < a2.researcher_id
            JOIN researcher r1 ON r1.id = a1.researcher_id
            JOIN researcher r2 ON r2.id = a2.researcher_id
            WHERE p.year >= 2010
        ''').fetchall()
    for left, right in rows:
        graph[left].add(right)
        graph[right].add(left)

    start = 'Dr. Alan Grant'
    goal = 'Dr. Ellie Sattler'
    queue = collections.deque([[start]])
    seen = {start}
    while queue:
        path = queue.popleft()
        if path[-1] == goal:
            return path, len(path) - 1
        for neighbor in sorted(graph[path[-1]]):
            if neighbor not in seen:
                seen.add(neighbor)
                queue.append(path + [neighbor])
    raise AssertionError('The verification database unexpectedly has no collaboration path.')


def install_dynamic_case():
    with sqlite3.connect(DB_PATH) as con:
        # Disable the original post-2010 chain and create a different, unique
        # post-2010 shortest path. The pre-2010 shortcut remains ineligible.
        con.execute('UPDATE publication SET year = 2001 WHERE id IN (103, 104, 105)')
        con.execute("INSERT INTO publication VALUES (900001, 'Dynamic Grant-Arnold Study', 2022)")
        con.execute('INSERT INTO authorship VALUES (1, 900001)')
        con.execute('INSERT INTO authorship VALUES (6, 900001)')
        con.execute("INSERT INTO publication VALUES (900002, 'Dynamic Arnold-Sattler Study', 2023)")
        con.execute('INSERT INTO authorship VALUES (6, 900002)')
        con.execute('INSERT INTO authorship VALUES (2, 900002)')
        con.commit()


def find_python_scripts():
    home = Path('/home/user')
    candidates = []
    skipped_dirs = {'.git', '.venv', 'venv', 'env', '__pycache__', 'site-packages', 'node_modules'}
    for root, dirs, files in os.walk(home):
        dirs[:] = [d for d in dirs if d not in skipped_dirs and not d.startswith('.')]
        for name in files:
            path = Path(root) / name
            if path == RESULT_PATH or not path.is_file():
                continue
            is_candidate = path.suffix.lower() == '.py'
            if not is_candidate:
                try:
                    first_line = path.open('rb').readline(256).lower()
                    is_candidate = first_line.startswith(b'#!') and b'python' in first_line
                except OSError:
                    pass
            if is_candidate:
                candidates.append(path)

    priority = {'solve.py': 0, 'solution.py': 1, 'main.py': 2}
    return sorted(set(candidates), key=lambda p: (priority.get(p.name.lower(), 10), len(p.parts), str(p)))


def run_script(script):
    try:
        completed = subprocess.run(
            [sys.executable, str(script)],
            cwd=str(script.parent),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        return completed.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


# Preserve the original verifier's existence, schema, and exact-value assertions.
assert_original_result()
original_result_bytes = RESULT_PATH.read_bytes()
sqlite_backup(DB_PATH, BACKUP_PATH)

scripts = find_python_scripts()
assert scripts, 'No Python script implementing the requested task was found under /home/user.'

accepted = None
try:
    for script in scripts:
        restore_database()
        install_dynamic_case()
        expected_path, expected_distance = expected_from_database()
        try:
            RESULT_PATH.unlink()
        except FileNotFoundError:
            pass

        if not run_script(script) or not RESULT_PATH.is_file():
            continue
        try:
            dynamic = load_result()
            if dynamic['path'] != expected_path or dynamic['distance'] != expected_distance:
                continue
        except (AssertionError, OSError, ValueError, TypeError):
            continue

        # The same executable script must also regenerate the required original answer.
        restore_database()
        try:
            RESULT_PATH.unlink()
        except FileNotFoundError:
            pass
        if not run_script(script):
            continue
        try:
            assert_original_result()
        except (AssertionError, OSError, ValueError, TypeError):
            continue
        accepted = script
        break

    assert accepted is not None, \
        'No submitted Python script regenerated correct results from both the original and modified database.'
finally:
    restore_database()
    if accepted is None:
        RESULT_PATH.write_bytes(original_result_bytes)

print(f'Validated executable solution script: {accepted}')
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
