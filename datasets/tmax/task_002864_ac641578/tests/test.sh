#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import shutil
import sqlite3
import subprocess

DB_PATH = '/home/user/audit_logs.db'
SOURCE_PATH = '/home/user/detect_deadlocks.c'
EXECUTABLE_PATH = '/home/user/detect_deadlocks'
OUTPUT_PATH = '/home/user/deadlocks.json'
COMPILED_PATH = '/tmp/detect_deadlocks_from_source'

EXPECTED_TRANSACTIONS = [
    (1, '2022-12-01 10:00:00'),
    (2, '2023-01-05 10:00:00'),
    (3, '2023-01-05 10:05:00'),
    (4, '2023-01-06 11:00:00'),
    (5, '2023-01-06 11:05:00'),
    (6, '2023-01-07 12:00:00'),
]

EXPECTED_REQUESTS = [
    (1, 2, 100, 'GRANTED'),
    (2, 3, 101, 'GRANTED'),
    (3, 2, 101, 'WAITING'),
    (4, 3, 100, 'WAITING'),
    (5, 4, 102, 'GRANTED'),
    (6, 5, 103, 'GRANTED'),
    (7, 4, 103, 'WAITING'),
    (8, 5, 102, 'WAITING'),
    (9, 6, 104, 'WAITING'),
    (10, 2, 104, 'GRANTED'),
    (11, 1, 105, 'GRANTED'),
    (12, 2, 106, 'GRANTED'),
    (13, 1, 106, 'WAITING'),
    (14, 2, 105, 'WAITING'),
]


def file_hash(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(65536), b''):
            h.update(chunk)
    return h.hexdigest()


def remove_sqlite_sidecars():
    for suffix in ('-wal', '-shm', '-journal'):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass


def assert_original_database_contents():
    assert os.path.exists(DB_PATH), 'Database /home/user/audit_logs.db was deleted'
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute('SELECT COUNT(*) FROM transactions')
        tx_count = cursor.fetchone()[0]
        assert tx_count == 6, 'Transactions table was modified (row count changed)'

        cursor.execute('SELECT COUNT(*) FROM lock_requests')
        req_count = cursor.fetchone()[0]
        assert req_count == 14, 'Lock requests table was modified (row count changed)'

        cursor.execute('SELECT tx_id, start_time FROM transactions ORDER BY tx_id')
        assert cursor.fetchall() == EXPECTED_TRANSACTIONS, 'Transactions table contents were modified'

        cursor.execute('SELECT req_id, tx_id, resource_id, status FROM lock_requests ORDER BY req_id')
        assert cursor.fetchall() == EXPECTED_REQUESTS, 'Lock requests table contents were modified'
    finally:
        conn.close()


def derive_expected(transactions, requests):
    starts = {tx_id: start_time for tx_id, start_time in transactions}
    eligible = {tx_id for tx_id, start_time in transactions
                if start_time > '2023-01-01 00:00:00'}
    waiting = [(tx, resource) for _, tx, resource, status in requests if status == 'WAITING']
    granted = [(tx, resource) for _, tx, resource, status in requests if status == 'GRANTED']

    edges = set()
    for waiter, resource in waiting:
        for holder, held_resource in granted:
            if (resource == held_resource and waiter != holder and
                    waiter in eligible and holder in eligible and
                    waiter in starts and holder in starts):
                edges.add((waiter, holder))

    pairs = []
    for first, second in edges:
        if first < second and (second, first) in edges:
            pairs.append({'tx1': first, 'tx2': second})
    return sorted(pairs, key=lambda item: (item['tx1'], item['tx2']))


def read_and_validate_output(expected):
    assert os.path.exists(OUTPUT_PATH), f'Output file {OUTPUT_PATH} is missing'
    try:
        with open(OUTPUT_PATH, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'Output file {OUTPUT_PATH} is not valid JSON: {exc}')

    assert isinstance(data, dict), 'JSON output must be an object'
    assert 'deadlocks' in data, "JSON output is missing 'deadlocks' key"
    assert set(data.keys()) == {'deadlocks'}, "JSON output contains keys outside the required schema"
    deadlocks = data['deadlocks']
    assert isinstance(deadlocks, list), "'deadlocks' should be a list"
    for pair in deadlocks:
        assert isinstance(pair, dict) and set(pair.keys()) == {'tx1', 'tx2'}, 'Invalid deadlock entry schema'
        assert type(pair['tx1']) is int and type(pair['tx2']) is int, 'Transaction IDs must be integers'
        assert pair['tx1'] < pair['tx2'], 'Each deadlock must have tx1 < tx2'

    assert len(deadlocks) == len(expected), f'Expected {len(expected)} deadlocks, found {len(deadlocks)}'
    for item in expected:
        assert item in deadlocks, f'Expected deadlock {item} not found in output'
    assert deadlocks == expected, f'Deadlocks are not sorted correctly. Expected: {expected}, Got: {deadlocks}'


def run_program(program, expected):
    try:
        os.remove(OUTPUT_PATH)
    except FileNotFoundError:
        pass
    before = file_hash(DB_PATH)
    result = subprocess.run([program], cwd='/home/user', stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=15)
    assert result.returncode == 0, f'{program} exited with {result.returncode}: {result.stderr}'
    assert file_hash(DB_PATH) == before, f'{program} modified /home/user/audit_logs.db'
    read_and_validate_output(expected)


def install_database(transactions, requests):
    remove_sqlite_sidecars()
    try:
        os.remove(DB_PATH)
    except FileNotFoundError:
        pass
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute('CREATE TABLE transactions (tx_id INTEGER PRIMARY KEY, start_time DATETIME)')
        cursor.execute('CREATE TABLE lock_requests (req_id INTEGER PRIMARY KEY, tx_id INTEGER, resource_id INTEGER, status TEXT)')
        cursor.executemany('INSERT INTO transactions VALUES (?, ?)', transactions)
        cursor.executemany('INSERT INTO lock_requests VALUES (?, ?, ?, ?)', requests)
        conn.commit()
    finally:
        conn.close()


def test_complete_solution():
    assert os.path.exists(SOURCE_PATH), 'C source file /home/user/detect_deadlocks.c is missing'
    assert os.path.isfile(SOURCE_PATH), '/home/user/detect_deadlocks.c is not a regular file'
    assert os.path.exists(EXECUTABLE_PATH), 'Executable /home/user/detect_deadlocks is missing'
    assert os.path.isfile(EXECUTABLE_PATH), '/home/user/detect_deadlocks is not a regular file'
    assert os.access(EXECUTABLE_PATH, os.X_OK), 'File /home/user/detect_deadlocks is not executable'
    with open(EXECUTABLE_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', '/home/user/detect_deadlocks is not a compiled executable'

    compile_result = subprocess.run(
        ['gcc', SOURCE_PATH, '-o', COMPILED_PATH, '-lsqlite3'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
    assert compile_result.returncode == 0, f'C source does not compile with SQLite3: {compile_result.stderr}'

    assert_original_database_contents()
    original_hash = file_hash(DB_PATH)
    backup_path = '/tmp/audit_logs.db.original'
    shutil.copyfile(DB_PATH, backup_path)

    try:
        initial_expected = [{'tx1': 2, 'tx2': 3}, {'tx1': 4, 'tx2': 5}]
        run_program(EXECUTABLE_PATH, initial_expected)
        run_program(COMPILED_PATH, initial_expected)

        ids = secrets.SystemRandom().sample(range(1000, 9000), 7)
        a, b, c, d, e, old, boundary = ids
        resource_base = secrets.randbelow(1000000) + 10000
        r1, r2, r3, r4, r5, r6, r7, r8 = range(resource_base, resource_base + 8)
        transactions = [
            (a, '2024-03-01 01:00:00'),
            (b, '2023-02-02 02:00:00'),
            (c, '2025-05-05 05:00:00'),
            (d, '2023-01-01 00:00:01'),
            (e, '2026-06-06 06:00:00'),
            (old, '2022-12-31 23:59:59'),
            (boundary, '2023-01-01 00:00:00'),
        ]
        requests = [
            (1, a, r1, 'GRANTED'), (2, b, r2, 'GRANTED'),
            (3, a, r2, 'WAITING'), (4, b, r1, 'WAITING'),
            (5, d, r3, 'GRANTED'), (6, e, r4, 'GRANTED'),
            (7, d, r4, 'WAITING'), (8, e, r3, 'WAITING'),
            (9, c, r1, 'WAITING'),
            (10, old, r5, 'GRANTED'), (11, b, r6, 'GRANTED'),
            (12, old, r6, 'WAITING'), (13, b, r5, 'WAITING'),
            (14, boundary, r7, 'GRANTED'), (15, c, r8, 'GRANTED'),
            (16, boundary, r8, 'WAITING'), (17, c, r7, 'WAITING'),
            (18, a, r2, 'WAITING'),
        ]
        expected = derive_expected(transactions, requests)
        install_database(transactions, requests)
        run_program(EXECUTABLE_PATH, expected)
        run_program(COMPILED_PATH, expected)

        no_deadlock_transactions = [
            (ids[0], '2024-01-01 00:00:00'),
            (ids[1], '2024-01-02 00:00:00'),
            (ids[2], '2022-01-01 00:00:00'),
        ]
        no_deadlock_requests = [
            (1, ids[0], r1, 'WAITING'),
            (2, ids[1], r1, 'GRANTED'),
            (3, ids[2], r2, 'WAITING'),
            (4, ids[0], r2, 'GRANTED'),
        ]
        expected = derive_expected(no_deadlock_transactions, no_deadlock_requests)
        install_database(no_deadlock_transactions, no_deadlock_requests)
        run_program(EXECUTABLE_PATH, expected)
        run_program(COMPILED_PATH, expected)
    finally:
        remove_sqlite_sidecars()
        shutil.copyfile(backup_path, DB_PATH)
        remove_sqlite_sidecars()

    assert file_hash(DB_PATH) == original_hash, 'Original database bytes were not preserved'
    assert_original_database_contents()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
