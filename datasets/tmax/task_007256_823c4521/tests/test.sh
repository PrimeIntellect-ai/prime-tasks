#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import importlib.util
import json
import os
import secrets
import sqlite3
import stat
import tempfile
from collections import Counter

PROCESSOR = '/home/user/processor.py'
INPUT = '/home/user/data/input.jsonl'
DB = '/home/user/transactions.db'


def load_processor():
    mode = os.lstat(PROCESSOR).st_mode
    assert stat.S_ISREG(mode), f'{PROCESSOR} must be a regular file.'
    spec = importlib.util.spec_from_file_location('submitted_processor', PROCESSOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def repaired_decode(payload):
    padded = payload + ('=' * (-len(payload) % 4))
    return base64.b64decode(padded, validate=True).decode('utf-8')


def read_expected_records():
    records = []
    malformed = []
    with open(INPUT, 'r', encoding='utf-8') as f:
        for line_number, line in enumerate(f, 1):
            rec = json.loads(line)
            assert set(rec) == {'id', 'payload'}, f'Unexpected input fields on line {line_number}.'
            try:
                base64.b64decode(rec['payload'], validate=True).decode('utf-8')
            except Exception:
                malformed.append(rec['id'])
            records.append((rec['id'], repaired_decode(rec['payload'])))

    assert len(records) == 1000, f'Expected 1000 input records, found {len(records)}.'
    assert malformed == ['TXN-0452'], f'Expected only TXN-0452 to have malformed padding, found {malformed}.'
    assert records == [(f'TXN-{i:04d}', f'Data for TXN-{i:04d}') for i in range(1, 1001)], \
        'The supplied transaction batch no longer matches the task input.'
    return records


def test_processor_functions_and_dynamic_pipeline():
    processor = load_processor()

    for text in ['x', 'xy', 'payload with spaces', 'Data for synthetic transaction']:
        encoded = base64.b64encode(text.encode('utf-8')).decode('ascii')
        assert processor.decode_payload(encoded.rstrip('=')) == text
        assert processor.decode_payload(encoded) == text

    for count in [0, 1, 99, 100, 101, 200, 237]:
        records = list(range(count))
        batches = processor.batch_records(records, 100)
        assert [item for batch in batches for item in batch] == records
        assert all(0 < len(batch) <= 100 for batch in batches)
        assert len(batches) == (count + 99) // 100

    token = secrets.token_hex(12)
    source_records = []
    expected = []
    for i in range(237):
        txn_id = f'DYNAMIC-{token}-{i}'
        text = f'dynamic payload {token} number {i}'
        payload = base64.b64encode(text.encode('utf-8')).decode('ascii')
        if i == 113:
            payload = payload.rstrip('=')
        source_records.append({'id': txn_id, 'payload': payload})
        expected.append((txn_id, text))

    with tempfile.TemporaryDirectory() as td:
        input_path = os.path.join(td, 'input.jsonl')
        db_path = os.path.join(td, 'transactions.db')
        with open(input_path, 'w', encoding='utf-8') as f:
            for rec in source_records:
                f.write(json.dumps(rec) + '\n')
        processor.process_file(input_path, db_path)
        with sqlite3.connect(db_path) as conn:
            actual = conn.execute('SELECT id, data FROM transactions').fetchall()
        assert Counter(actual) == Counter(expected)


def test_crash_id_file():
    file_path = '/home/user/crash_id.txt'
    assert os.path.isfile(file_path), f'File {file_path} does not exist.'
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()
    assert content == 'TXN-0452', f"Expected 'TXN-0452' in {file_path}, but found '{content}'."


def test_total_processed_file():
    file_path = '/home/user/total_processed.txt'
    assert os.path.isfile(file_path), f'File {file_path} does not exist.'
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read().strip()
    assert content == '1000', f"Expected '1000' in {file_path}, but found '{content}'."


def test_database_records():
    expected = read_expected_records()
    assert os.path.isfile(DB), f'Database file {DB} does not exist.'

    with sqlite3.connect(DB) as conn:
        c = conn.cursor()
        c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='transactions'")
        assert c.fetchone() is not None, "Table 'transactions' does not exist in the database."

        c.execute('SELECT COUNT(*) FROM transactions')
        count = c.fetchone()[0]
        assert count == 1000, f'Expected 1000 records in the database, but found {count}.'

        c.execute("SELECT data FROM transactions WHERE id = 'TXN-0452'")
        row = c.fetchone()
        assert row is not None, "Record 'TXN-0452' is missing from the database."
        assert row[0] == 'Data for TXN-0452', \
            f"Expected decoded data 'Data for TXN-0452', but got '{row[0]}'."

        c.execute('SELECT id, data FROM transactions')
        actual = c.fetchall()

    assert Counter(actual) == Counter(expected), \
        'The database does not exactly contain every decoded input transaction.'
TEST_EOF

# Remove any prebuilt database and require the submitted program to recreate it.
rm -f /home/user/transactions.db
if [ -f /home/user/processor.py ] && timeout 30s python3 /home/user/processor.py && \
   python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
