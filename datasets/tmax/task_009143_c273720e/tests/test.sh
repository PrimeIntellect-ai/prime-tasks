#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import os
import sqlite3
import subprocess
from collections import Counter, defaultdict

RAW_PATH = '/home/user/data/raw_events.csv'
CLEAN_PATH = '/home/user/data/clean_events.csv'
SAMPLED_PATH = '/home/user/data/sampled_events.csv'
DB_PATH = '/home/user/data/analytics.db'
SCRIPT_PATH = '/home/user/process_pipeline.py'
HEADER = ['event_id', 'user_id', 'event_type', 'timestamp', 'payload']


def row_tuple(row):
    return tuple(row[column] for column in HEADER)


def read_csv(path):
    assert os.path.isfile(path), f'Required CSV {path} does not exist.'
    with open(path, newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == HEADER, f'{path} has incorrect header: {reader.fieldnames}'
        return [row_tuple(row) for row in reader]


def derive_expected():
    with open(RAW_PATH, 'rb') as f:
        raw_digest = hashlib.sha256(f.read()).hexdigest()

    expected_clean = []
    seen_hashes = set()
    with open(RAW_PATH, newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == HEADER, f'Raw CSV has incorrect header: {reader.fieldnames}'
        for row in reader:
            h = hashlib.md5(
                f"{row['user_id']}{row['event_type']}{row['payload']}".encode('utf-8')
            ).hexdigest()
            if h not in seen_hashes:
                seen_hashes.add(h)
                expected_clean.append(row_tuple(row))

    groups = defaultdict(list)
    for row in expected_clean:
        groups[row[2]].append(row)

    expected_sample = []
    for event_type in groups:
        group = sorted(groups[event_type], key=lambda row: row[0])
        expected_sample.extend(group[::10])

    return raw_digest, expected_clean, expected_sample


def test_pipeline_outputs_match_raw_data():
    assert os.path.isfile(SCRIPT_PATH), f'Pipeline script {SCRIPT_PATH} does not exist.'
    assert os.path.isfile(RAW_PATH), f'Raw data {RAW_PATH} does not exist.'

    raw_digest, expected_clean, expected_sample = derive_expected()

    for path in (CLEAN_PATH, SAMPLED_PATH, DB_PATH):
        if os.path.lexists(path):
            os.remove(path)

    subprocess.run(['python3', SCRIPT_PATH], check=True, timeout=300)

    with open(RAW_PATH, 'rb') as f:
        assert hashlib.sha256(f.read()).hexdigest() == raw_digest, 'Pipeline modified raw_events.csv.'

    actual_clean = read_csv(CLEAN_PATH)
    actual_sample = read_csv(SAMPLED_PATH)

    # The clean CSV must preserve the first raw record for each deduplication hash.
    assert actual_clean == expected_clean, 'clean_events.csv does not match first-occurrence hash deduplication of raw_events.csv.'
    assert Counter(actual_sample) == Counter(expected_sample), 'sampled_events.csv does not contain the required deterministic stratified sample.'
    assert len(actual_sample) == len(expected_sample), 'sampled_events.csv has an incorrect row count.'

    # Retain the original deduplication assertion, using the data-derived count.
    assert len(actual_clean) == len(expected_clean), f'Expected {len(expected_clean)} clean events, got {len(actual_clean)}.'
    seen_hashes = set()
    for event_id, user_id, event_type, timestamp, payload in actual_clean:
        h = hashlib.md5(f'{user_id}{event_type}{payload}'.encode('utf-8')).hexdigest()
        assert h not in seen_hashes, f'Found duplicate hash for user_id={user_id}, event_type={event_type}, payload={payload}!'
        seen_hashes.add(h)

    assert os.path.isfile(DB_PATH), f'Database file {DB_PATH} does not exist.'
    conn = sqlite3.connect(DB_PATH)
    try:
        cur = conn.cursor()
        for table, expected_rows in (
            ('clean_events', expected_clean),
            ('sampled_events', expected_sample),
        ):
            cur.execute(f'PRAGMA table_info({table})')
            schema = [(row[1], row[2].upper()) for row in cur.fetchall()]
            assert schema == [(column, 'TEXT') for column in HEADER], f'{table} has incorrect schema: {schema}'

            cur.execute(f'SELECT event_id, user_id, event_type, timestamp, payload FROM {table}')
            db_rows = cur.fetchall()
            assert len(db_rows) == len(expected_rows), f'Expected {len(expected_rows)} rows in {table}, got {len(db_rows)}.'
            assert Counter(db_rows) == Counter(expected_rows), f'{table} contents do not match the required CSV-derived data.'

        # Retain the original per-stratum count and every-tenth selection checks.
        cur.execute('SELECT event_type, COUNT(*) FROM clean_events GROUP BY event_type')
        strata_counts = dict(cur.fetchall())
        cur.execute('SELECT event_type, COUNT(*) FROM sampled_events GROUP BY event_type')
        sample_counts = dict(cur.fetchall())
        assert set(sample_counts).issubset(set(strata_counts)), 'sampled_events contains an unknown event_type.'
        for event_type, count in strata_counts.items():
            expected_count = (count + 9) // 10
            assert sample_counts.get(event_type, 0) == expected_count, (
                f'Expected {expected_count} sampled events for {event_type}, '
                f'got {sample_counts.get(event_type, 0)}.'
            )

        clean_ids = defaultdict(list)
        for event_id, user_id, event_type, timestamp, payload in expected_clean:
            clean_ids[event_type].append(event_id)
        for event_type in clean_ids:
            clean_ids[event_type].sort()

        for event_id, user_id, event_type, timestamp, payload in actual_sample:
            index = clean_ids[event_type].index(event_id)
            assert index % 10 == 0, f'Sampled event {event_id} for {event_type} is at index {index}, not a multiple of 10.'
    finally:
        conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
