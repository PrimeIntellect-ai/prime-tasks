#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import sqlite3
import subprocess

C_FILE = '/home/user/generate_manifest.c'
DB_FILE = '/home/user/backup_meta.db'
MANIFEST = '/home/user/pending_backups.txt'
BINARY = '/tmp/generate_manifest_test'


def run_program():
    if os.path.exists(MANIFEST):
        os.remove(MANIFEST)
    result = subprocess.run([BINARY], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, (
        'Compiled program failed.\nstdout:\n' + result.stdout +
        '\nstderr:\n' + result.stderr
    )
    assert os.path.isfile(MANIFEST), f'Manifest file {MANIFEST} is missing.'
    with open(MANIFEST, 'r') as f:
        return f.read().strip()


def test_c_source_exists():
    assert os.path.isfile(C_FILE), f'C source file {C_FILE} is missing.'


def test_manifest_exists_and_content():
    with open(C_FILE, 'r') as f:
        source = f.read()

    assert 'sqlite3.h' in source, 'The program must include sqlite3.h.'
    assert 'sqlite3_open' in source or 'sqlite3_open_v2' in source, (
        'The program must open the database through the SQLite3 C API.'
    )
    assert 'sqlite3_exec' in source or 'sqlite3_prepare' in source, (
        'The program must execute its query through the SQLite3 C API.'
    )

    build = subprocess.run(
        ['gcc', C_FILE, '-o', BINARY, '-lsqlite3'],
        capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, (
        'C program did not compile with SQLite3.\nstdout:\n' + build.stdout +
        '\nstderr:\n' + build.stderr
    )

    content = run_program()
    expected_lines = [
        'audit_logs',
        'order_items',
        'orders'
    ]
    expected_content = '\n'.join(expected_lines)
    assert content == expected_content, (
        'Manifest content does not match the expected output.\n'
        f'Expected:\n{expected_content}\n\nGot:\n{content}'
    )


def expected_stale(rows, backups, dependencies):
    latest = {}
    for table_id, backup_time in backups:
        latest[table_id] = max(latest.get(table_id, backup_time), backup_time)

    stale = {
        table_id for table_id, name, last_update in rows
        if table_id not in latest or last_update > latest[table_id]
    }
    changed = True
    while changed:
        changed = False
        for parent_id, child_id in dependencies:
            if parent_id in stale and child_id not in stale:
                stale.add(child_id)
                changed = True

    return sorted(name for table_id, name, last_update in rows if table_id in stale)


def install_database(rows, backups, dependencies):
    if os.path.exists(DB_FILE):
        os.remove(DB_FILE)
    conn = sqlite3.connect(DB_FILE)
    try:
        conn.executescript('''
            CREATE TABLE tables (id INTEGER PRIMARY KEY, name TEXT, last_update INTEGER);
            CREATE TABLE backups (id INTEGER PRIMARY KEY, table_id INTEGER, backup_time INTEGER);
            CREATE TABLE dependencies (parent_id INTEGER, child_id INTEGER);
        ''')
        conn.executemany('INSERT INTO tables VALUES (?, ?, ?)', rows)
        conn.executemany(
            'INSERT INTO backups (table_id, backup_time) VALUES (?, ?)', backups
        )
        conn.executemany('INSERT INTO dependencies VALUES (?, ?)', dependencies)
        conn.commit()
    finally:
        conn.close()


def test_program_queries_database_and_handles_recursive_dependencies():
    saved_db = '/tmp/original_backup_meta.db'
    shutil.copy2(DB_FILE, saved_db)
    rng = random.Random(secrets.randbits(64))

    try:
        for case in range(3):
            count = 9
            names = [f't_{secrets.token_hex(4)}_{i}' for i in range(count)]
            rows = []
            backups = []

            for i in range(count):
                table_id = i + 1
                update = rng.randint(200, 5000)
                rows.append((table_id, names[i], update))
                mode = (i + case) % 4
                if mode == 0:
                    pass
                elif mode == 1:
                    backups.append((table_id, update - rng.randint(1, 40)))
                    backups.append((table_id, update - 1))
                elif mode == 2:
                    backups.append((table_id, update - rng.randint(1, 40)))
                    backups.append((table_id, update + rng.randint(1, 40)))
                else:
                    backups.append((table_id, update))

            dependencies = [(1, 4), (4, 7), (2, 5), (5, 8)]
            for parent in range(1, count + 1):
                for child in range(parent + 1, count + 1):
                    edge = (parent, child)
                    if edge not in dependencies and rng.random() < 0.12:
                        dependencies.append(edge)

            install_database(rows, backups, dependencies)
            expected = '\n'.join(expected_stale(rows, backups, dependencies))
            actual = run_program()
            assert actual == expected, (
                'Program did not derive the manifest from the current database, '
                'including latest-backup and transitive-dependency rules.\n'
                f'Expected:\n{expected}\n\nGot:\n{actual}'
            )
    finally:
        shutil.copy2(saved_db, DB_FILE)
        run_program()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
