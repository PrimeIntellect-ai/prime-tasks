#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import subprocess
import uuid

import pytest

SCRIPT_PATH = '/home/user/analyze_backups.sh'
OUTPUT_PATH = '/home/user/restore_plan.txt'
DB_PATH = '/home/user/db_metadata.sqlite'


def run_script(target, cutoff):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [SCRIPT_PATH, target, cutoff],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f'Script failed with error: {result.stderr}'
    assert os.path.isfile(OUTPUT_PATH), f'Output file {OUTPUT_PATH} was not created.'
    with open(OUTPUT_PATH, 'r') as f:
        return f.read().strip()


def derive_expected(target, cutoff):
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute('SELECT id, name FROM databases').fetchall()
        names = {db_id: name for db_id, name in rows}
        target_row = conn.execute(
            'SELECT id FROM databases WHERE name = ?', (target,)
        ).fetchone()
        assert target_row is not None
        target_id = target_row[0]

        parents = {}
        for parent_id, child_id in conn.execute(
            'SELECT parent_id, child_id FROM dependencies'
        ):
            parents.setdefault(child_id, []).append(parent_id)

        max_depth = {}
        stack = [(target_id, 0)]
        while stack:
            db_id, depth = stack.pop()
            if depth <= max_depth.get(db_id, -1):
                continue
            max_depth[db_id] = depth
            for parent_id in parents.get(db_id, []):
                stack.append((parent_id, depth + 1))

        ordered = sorted(
            max_depth,
            key=lambda db_id: (-max_depth[db_id], names[db_id]),
        )
        selected = []
        total = 0
        for db_id in ordered:
            backup = conn.execute(
                """SELECT id, size_bytes, backup_timestamp
                   FROM backups
                   WHERE db_id = ? AND status = 'SUCCESS'
                     AND backup_timestamp < ?
                   ORDER BY backup_timestamp DESC
                   LIMIT 1""",
                (db_id, cutoff),
            ).fetchone()
            assert backup is not None, f'Test fixture lacks a backup for {names[db_id]}'
            backup_id, size_bytes, timestamp = backup
            total += size_bytes
            selected.append((names[db_id], backup_id, timestamp))

        lines = [f'Total Size: {total}', 'Restoration Order:']
        for number, (name, backup_id, timestamp) in enumerate(selected, 1):
            lines.append(f'{number}. {name} - {backup_id} - {timestamp}')
        return '\n'.join(lines)
    finally:
        conn.close()


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f'Script {SCRIPT_PATH} does not exist.'
    assert os.access(SCRIPT_PATH, os.X_OK), f'Script {SCRIPT_PATH} is not executable.'


def test_output_format_and_logic_analytics():
    content = run_script('analytics', '2023-10-01 00:00:00')
    expected_content = """Total Size: 10000
Restoration Order:
1. core_inventory - 201 - 2023-09-28 10:00:00
2. core_users - 101 - 2023-09-29 10:00:00
3. orders - 301 - 2023-09-30 05:00:00
4. analytics - 401 - 2023-09-30 06:00:00"""
    assert content == expected_content, f"Output content did not match expected for 'analytics'.\nExpected:\n{expected_content}\n\nGot:\n{content}"


def test_dynamic_logic_reporting():
    content = run_script('reporting', '2023-10-01 00:00:00')
    expected_content = """Total Size: 15000
Restoration Order:
1. core_inventory - 201 - 2023-09-28 10:00:00
2. core_users - 101 - 2023-09-29 10:00:00
3. orders - 301 - 2023-09-30 05:00:00
4. analytics - 401 - 2023-09-30 06:00:00
5. reporting - 501 - 2023-09-30 07:00:00"""
    assert content == expected_content, f"Output content did not match expected for 'reporting'. The script might have hardcoded outputs.\nExpected:\n{expected_content}\n\nGot:\n{content}"


@pytest.fixture
def generated_graph():
    prefix = 'verify_' + uuid.uuid4().hex
    labels = ['deep', 'alpha', 'root', 'mid', 'side', 'target']
    db_names = {label: f'{prefix}_{label}' for label in labels}
    conn = sqlite3.connect(DB_PATH)
    ids = {}
    try:
        for label in labels:
            cursor = conn.execute(
                'INSERT INTO databases(name) VALUES (?)', (db_names[label],)
            )
            ids[label] = cursor.lastrowid

        edges = [
            ('deep', 'root'),
            ('root', 'mid'),
            ('root', 'target'),
            ('alpha', 'mid'),
            ('mid', 'target'),
            ('side', 'target'),
        ]
        conn.executemany(
            'INSERT INTO dependencies(parent_id, child_id) VALUES (?, ?)',
            [(ids[parent], ids[child]) for parent, child in edges],
        )

        for index, label in enumerate(labels):
            db_id = ids[label]
            conn.execute(
                "INSERT INTO backups(db_id, size_bytes, backup_timestamp, status) VALUES (?, ?, ?, 'SUCCESS')",
                (db_id, 1000 + index * 137, f'2024-01-01 00:{index:02d}:00'),
            )
            conn.execute(
                "INSERT INTO backups(db_id, size_bytes, backup_timestamp, status) VALUES (?, ?, ?, 'FAILED')",
                (db_id, 8000 + index, f'2024-02-01 00:{index:02d}:00'),
            )
            conn.execute(
                "INSERT INTO backups(db_id, size_bytes, backup_timestamp, status) VALUES (?, ?, '2024-03-01 00:00:00', 'SUCCESS')",
                (db_id, 3000 + index * 211),
            )
            conn.execute(
                "INSERT INTO backups(db_id, size_bytes, backup_timestamp, status) VALUES (?, ?, ?, 'SUCCESS')",
                (db_id, 5000 + index * 313, f'2024-03-02 00:{index:02d}:00'),
            )
        conn.commit()
    finally:
        conn.close()

    try:
        yield db_names
    finally:
        conn = sqlite3.connect(DB_PATH)
        try:
            generated_ids = list(ids.values())
            placeholders = ','.join('?' for _ in generated_ids)
            conn.execute(
                f'DELETE FROM backups WHERE db_id IN ({placeholders})', generated_ids
            )
            conn.execute(
                f'DELETE FROM dependencies WHERE parent_id IN ({placeholders}) OR child_id IN ({placeholders})',
                generated_ids + generated_ids,
            )
            conn.execute(
                f'DELETE FROM databases WHERE id IN ({placeholders})', generated_ids
            )
            conn.commit()
        finally:
            conn.close()


def test_generated_graph_and_cutoffs(generated_graph):
    target = generated_graph['target']

    first_cutoff = '2024-03-01 00:00:00'
    expected = derive_expected(target, first_cutoff)
    assert run_script(target, first_cutoff) == expected

    second_cutoff = '2024-04-01 00:00:00'
    expected = derive_expected(target, second_cutoff)
    assert run_script(target, second_cutoff) == expected


def test_requires_exactly_two_arguments_and_valid_timestamp():
    invalid_argv = [
        [],
        ['analytics'],
        ['analytics', '2023-10-01 00:00:00', 'extra'],
        ['analytics', 'not-a-timestamp'],
    ]
    for args in invalid_argv:
        result = subprocess.run(
            [SCRIPT_PATH] + args,
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode != 0, f'Invalid arguments were accepted: {args!r}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
