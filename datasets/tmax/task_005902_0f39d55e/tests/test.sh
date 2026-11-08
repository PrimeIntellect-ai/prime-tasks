#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import re
import sqlite3
import subprocess
import sys
import uuid

SCRIPT_PATH = '/home/user/generate_plan.py'
CSV_PATH = '/home/user/restore_plan.csv'
DB_PATH = '/home/user/backup_metadata.db'
HEADER = ['step_number', 'backup_id', 'cumulative_size_mb']


def read_csv():
    assert os.path.isfile(CSV_PATH), f"CSV output file missing at {CSV_PATH}"
    with open(CSV_PATH, 'r', newline='') as f:
        return list(csv.reader(f))


def expected_plan(target):
    conn = sqlite3.connect(DB_PATH)
    try:
        row = conn.execute(
            'SELECT id, type, size_mb, parent_id FROM backups '
            'WHERE timestamp <= ? ORDER BY timestamp DESC LIMIT 1',
            (target,),
        ).fetchone()
        chain = []
        seen = set()
        while row is not None:
            backup_id, backup_type, size_mb, parent_id = row
            assert backup_id not in seen, 'Test database unexpectedly contains a dependency cycle'
            seen.add(backup_id)
            chain.append((backup_id, backup_type, size_mb))
            if parent_id is None:
                break
            row = conn.execute(
                'SELECT id, type, size_mb, parent_id FROM backups WHERE id = ?',
                (parent_id,),
            ).fetchone()
            assert row is not None, 'Test database unexpectedly contains a missing parent'

        if not chain:
            return [HEADER]
        assert chain[-1][1] == 'FULL', 'Dependency chain does not terminate at a FULL backup'
        chain.reverse()
        total = 0
        result = [HEADER]
        for step, (backup_id, _backup_type, size_mb) in enumerate(chain, 1):
            total += size_mb
            result.append([str(step), backup_id, str(total)])
        return result
    finally:
        conn.close()


def run_script(target):
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH, target],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Script failed for target {target!r} with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert read_csv() == expected_plan(target)


def test_01_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Script file missing at {SCRIPT_PATH}"


def test_02_original_csv_exists_and_correct():
    expected_rows = [
        ['step_number', 'backup_id', 'cumulative_size_mb'],
        ['1', 'bkp_005', '5200'],
        ['2', 'bkp_006', '5250'],
    ]
    actual_rows = read_csv()
    assert actual_rows == expected_rows, (
        f"CSV content does not match expected output. Expected: {expected_rows}, "
        f"Actual: {actual_rows}"
    )


def test_03_script_contains_required_sql_features():
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    ast.parse(source, filename=SCRIPT_PATH)

    assert re.search(r'\bOVER\s*\(', source, flags=re.IGNORECASE), (
        'The script must use a SQL window function with an OVER clause'
    )

    tree = ast.parse(source, filename=SCRIPT_PATH)
    parameterized_execute = any(
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr in {'execute', 'executemany'}
        and (len(node.args) >= 2 or any(
            kw.arg in {'parameters', 'params'} for kw in node.keywords
        ))
        for node in ast.walk(tree)
    )
    assert parameterized_execute, (
        'No parameterized SQLite execute call was found; pass the target timestamp '
        'separately from the SQL text'
    )


def test_04_execute_for_original_and_other_existing_targets():
    for target in (
        '2023-11-03 12:00:00',
        '2023-11-05 14:30:00',
        '2023-11-05 18:00:00',
        '2023-11-06 12:00:00',
    ):
        run_script(target)


def test_05_random_dependency_chain():
    token = uuid.uuid4().hex
    full_id = 'full_' + token
    inc1_id = 'inc1_' + token
    inc2_id = 'inc2_' + token
    sizes = (6101, 223, 347)
    rows = [
        (full_id, 'FULL', '2041-01-01 00:00:00', sizes[0], None),
        (inc1_id, 'INCREMENTAL', '2041-01-02 00:00:00', sizes[1], full_id),
        (inc2_id, 'INCREMENTAL', '2041-01-03 00:00:00', sizes[2], inc1_id),
    ]

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executemany(
            'INSERT INTO backups (id, type, timestamp, size_mb, parent_id) '
            'VALUES (?, ?, ?, ?, ?)',
            rows,
        )
        conn.commit()
    finally:
        conn.close()

    try:
        run_script('2041-01-03 12:34:56')
    finally:
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.executemany('DELETE FROM backups WHERE id = ?', [(r[0],) for r in rows])
            conn.commit()
        finally:
            conn.close()


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
