#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import struct
import sqlite3
import subprocess
import sys
import tempfile
import shutil
import secrets
from collections import Counter

import pytest

APP_DIR = '/home/user/app'
INGEST_PATH = '/home/user/app/ingest.py'
DB_PATH = '/home/user/app/logs.db'
LOG_DIR = '/home/user/logs'


def get_expected_records(log_dir=LOG_DIR):
    records = []
    files = sorted(glob.glob(os.path.join(log_dir, '*.bin')))
    for path in files:
        with open(path, 'rb') as fp:
            magic = fp.read(4)
            if magic != b'LOGS':
                continue

            count_data = fp.read(2)
            if len(count_data) < 2:
                continue
            count = struct.unpack('>H', count_data)[0]

            for _ in range(count):
                ts_data = fp.read(4)
                assert len(ts_data) == 4, f'Unexpected EOF in verifier input {path}'
                timestamp = struct.unpack('>I', ts_data)[0]

                status_data = fp.read(1)
                assert len(status_data) == 1, f'Unexpected EOF in verifier input {path}'
                status = struct.unpack('B', status_data)[0]

                len_data = fp.read(1)
                assert len(len_data) == 1, f'Unexpected EOF in verifier input {path}'
                msg_len = struct.unpack('B', len_data)[0]

                if msg_len == 255:
                    continue

                msg_data = fp.read(msg_len)
                assert len(msg_data) == msg_len, f'Unexpected EOF in verifier input {path}'
                message = msg_data.decode('utf-8', errors='ignore')
                records.append((timestamp, status, message))

    return records


def get_expected_counts(log_dir=LOG_DIR):
    records = get_expected_records(log_dir)
    return len(records), sum(1 for _, status, _ in records if status == 1)


def write_log(path, records):
    with open(path, 'wb') as fp:
        fp.write(b'LOGS')
        fp.write(struct.pack('>H', len(records)))
        for timestamp, status, message in records:
            fp.write(struct.pack('>I', timestamp))
            fp.write(struct.pack('B', status))
            if message is None:
                fp.write(b'\xff')
            else:
                encoded = message.encode('utf-8')
                assert len(encoded) < 255
                fp.write(struct.pack('B', len(encoded)))
                fp.write(encoded)


def run_ingest():
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    result = subprocess.run(
        [sys.executable, INGEST_PATH],
        cwd=APP_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        'The repaired ingestion script did not complete successfully.\n'
        f'stdout: {result.stdout}\nstderr: {result.stderr}'
    )
    assert os.path.isfile(DB_PATH), 'The ingestion script did not create logs.db.'


def assert_database_exact(expected_records):
    conn = sqlite3.connect(DB_PATH)
    try:
        columns = conn.execute('PRAGMA table_info(logs)').fetchall()
        assert [(row[1], row[2].upper()) for row in columns] == [
            ('timestamp', 'INTEGER'),
            ('status', 'INTEGER'),
            ('message', 'TEXT'),
        ], 'The logs database schema was modified.'

        actual_records = conn.execute(
            'SELECT timestamp, status, message FROM logs'
        ).fetchall()
    finally:
        conn.close()

    assert Counter(actual_records) == Counter(expected_records), (
        'The database does not contain the exact timestamp, status, and message '
        'values parsed from all non-deleted records.'
    )


@pytest.fixture(scope='session', autouse=True)
def executed_submission():
    assert os.path.isfile(INGEST_PATH), f'Required ingestion script {INGEST_PATH} is missing.'
    assert not os.path.islink(INGEST_PATH), f'{INGEST_PATH} must be a real Python source file.'
    with open(INGEST_PATH, 'rb') as fp:
        compile(fp.read(), INGEST_PATH, 'exec')

    original_records = get_expected_records()
    original_counts = get_expected_counts()

    backup_root = tempfile.mkdtemp(prefix='verifier_logs_', dir='/home/user')
    backup_logs = os.path.join(backup_root, 'logs')
    os.rename(LOG_DIR, backup_logs)
    os.mkdir(LOG_DIR)

    hidden_error = None
    try:
        nonce = secrets.token_hex(8)
        base = secrets.randbelow(500000000) + 1000000000
        write_log(os.path.join(LOG_DIR, 'probe_01.bin'), [
            (base, 1, 'before-' + nonce),
            (base + 1, 9, None),
            (base + 2, 2, 'after-' + nonce),
        ])
        write_log(os.path.join(LOG_DIR, 'probe_02.bin'), [
            (base + 3, 1, None),
            (base + 4, 1, 'tail-' + nonce),
            (base + 5, 0, ''),
        ])
        with open(os.path.join(LOG_DIR, 'ignored.bin'), 'wb') as fp:
            fp.write(b'NOPE' + secrets.token_bytes(12))

        hidden_expected = get_expected_records()
        run_ingest()
        assert_database_exact(hidden_expected)
    except BaseException as exc:
        hidden_error = exc
    finally:
        shutil.rmtree(LOG_DIR, ignore_errors=True)
        os.rename(backup_logs, LOG_DIR)
        shutil.rmtree(backup_root, ignore_errors=True)

    if hidden_error is not None:
        raise hidden_error

    run_ingest()
    assert_database_exact(original_records)
    return original_records, original_counts


def test_status_1_count_file(executed_submission):
    output_path = '/home/user/app/status_1_count.txt'
    assert os.path.isfile(output_path), f'Output file {output_path} is missing. Did you write the final count to it?'

    _, expected_status_1 = executed_submission[1]

    with open(output_path, 'r') as f:
        content = f.read().strip()

    assert content.isdigit(), f'File {output_path} does not contain a valid integer.'
    assert int(content) == expected_status_1, f'Expected count {expected_status_1}, but got {content} in {output_path}.'


def test_database_records_count(executed_submission):
    assert os.path.isfile(DB_PATH), f'Database file {DB_PATH} is missing. Did the script run successfully?'

    expected_records, (expected_total, expected_status_1) = executed_submission

    conn = sqlite3.connect(DB_PATH)
    try:
        c = conn.cursor()
        c.execute('SELECT COUNT(*) FROM logs')
        actual_total = c.fetchone()[0]

        c.execute('SELECT COUNT(*) FROM logs WHERE status = 1')
        actual_status_1 = c.fetchone()[0]

        actual_records = c.execute(
            'SELECT timestamp, status, message FROM logs'
        ).fetchall()
    finally:
        conn.close()

    assert actual_total == expected_total, f'Expected {expected_total} total records in database, but found {actual_total}. The parsing logic might not be correctly skipping deleted records or might be crashing.'
    assert actual_status_1 == expected_status_1, f'Expected {expected_status_1} records with status 1 in database, but found {actual_status_1}.'
    assert Counter(actual_records) == Counter(expected_records), 'Database rows do not exactly match the parsed non-deleted log records.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
