#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import unicodedata
import xml.etree.ElementTree as ET
from collections import Counter

import pyarrow as pa
import pyarrow.parquet as pq

RAW_DIR = '/home/user/raw_data'
OUTPUT_DIR = '/home/user/output'
PRIMES = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97]


def fingerprint(message):
    normalized = unicodedata.normalize('NFKC', message).lower()
    return sum(ord(char) * PRIMES[i % 25] for i, char in enumerate(normalized)) % 1000000007


def read_source_records():
    records = []

    with open(os.path.join(RAW_DIR, 'data.csv'), newline='', encoding='utf-8') as f:
        for row in csv.DictReader(f):
            records.append({
                'user_id': int(row['user_id']),
                'timestamp': int(row['timestamp']),
                'message': row['message'],
            })

    with open(os.path.join(RAW_DIR, 'data.jsonl'), encoding='utf-8') as f:
        for line in f:
            row = json.loads(line)
            records.append({
                'user_id': int(row['uid']),
                'timestamp': int(row['ts']),
                'message': row['msg'],
            })

    root = ET.parse(os.path.join(RAW_DIR, 'data.xml')).getroot()
    for row in root.findall('record'):
        records.append({
            'user_id': int(row.findtext('id')),
            'timestamp': int(row.findtext('time')),
            'message': row.findtext('text'),
        })

    return records


def derive_expected(records):
    kept = {}
    discarded_by_user = Counter()

    for record in records:
        candidate = dict(record)
        candidate['fingerprint'] = fingerprint(candidate['message'])
        key = (candidate['user_id'], candidate['fingerprint'])

        if key not in kept:
            kept[key] = candidate
        else:
            discarded_by_user[candidate['user_id']] += 1
            if candidate['timestamp'] < kept[key]['timestamp']:
                kept[key] = candidate

    expected_records = list(kept.values())
    duplicate_total = len(records) - len(expected_records)
    most_duplicates = max(discarded_by_user, key=discarded_by_user.get)
    expected_report = {
        'total_records_read': len(records),
        'total_duplicates_removed': duplicate_total,
        'user_with_most_duplicates': most_duplicates,
    }
    return expected_records, expected_report


SOURCE_RECORDS = read_source_records()
EXPECTED_SOURCE_RECORDS = [
    {'user_id': 1, 'timestamp': 1600000000, 'message': 'Hello World!'},
    {'user_id': 1, 'timestamp': 1600000010, 'message': 'hello world!'},
    {'user_id': 3, 'timestamp': 1600000003, 'message': 'こんにちは'},
    {'user_id': 4, 'timestamp': 1600000000, 'message': 'Unique message'},
    {'user_id': 1, 'timestamp': 1600000020, 'message': 'HELLO WORLD!'},
    {'user_id': 2, 'timestamp': 1600000005, 'message': 'Café'},
    {'user_id': 2, 'timestamp': 1600000015, 'message': 'Cafe\u0301'},
    {'user_id': 3, 'timestamp': 1600000000, 'message': 'こんにちは'},
    {'user_id': 3, 'timestamp': 1600000001, 'message': 'こんにちは'},
    {'user_id': 3, 'timestamp': 1600000002, 'message': 'こんにちは'},
]
EXPECTED_RECORDS, EXPECTED_REPORT = derive_expected(SOURCE_RECORDS)


def test_raw_inputs_are_intact():
    assert SOURCE_RECORDS == EXPECTED_SOURCE_RECORDS, 'The supplied raw input records were modified.'


def test_report_json_content():
    report_path = os.path.join(OUTPUT_DIR, 'report.json')
    assert os.path.exists(report_path), f'The file {report_path} does not exist.'

    with open(report_path, 'r', encoding='utf-8') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, f'The file {report_path} is not valid JSON.'

    assert 'total_records_read' in report, "Missing 'total_records_read' in report.json"
    assert report['total_records_read'] == 10, f"Expected 10 total_records_read, got {report['total_records_read']}"
    assert 'total_duplicates_removed' in report, "Missing 'total_duplicates_removed' in report.json"
    assert report['total_duplicates_removed'] == 6, f"Expected 6 total_duplicates_removed, got {report['total_duplicates_removed']}"
    assert 'user_with_most_duplicates' in report, "Missing 'user_with_most_duplicates' in report.json"
    assert report['user_with_most_duplicates'] == 3, f"Expected user 3 to have most duplicates, got {report['user_with_most_duplicates']}"

    assert set(report) == set(EXPECTED_REPORT), f'Unexpected report keys: {set(report) - set(EXPECTED_REPORT)}'
    for key in EXPECTED_REPORT:
        assert type(report[key]) is int, f'{key} must be an integer.'
    assert report == EXPECTED_REPORT, f'Incorrect report: expected {EXPECTED_REPORT}, got {report}'


def test_parquet_file_exists_and_content():
    parquet_path = os.path.join(OUTPUT_DIR, 'clean_data.parquet')
    assert os.path.exists(parquet_path), f'The file {parquet_path} does not exist.'
    assert os.path.getsize(parquet_path) > 0, f'The file {parquet_path} is empty.'

    table = pq.read_table(parquet_path)
    assert table.column_names == ['user_id', 'timestamp', 'message', 'fingerprint'], \
        f'Incorrect Parquet columns or order: {table.column_names}'

    expected_types = {
        'user_id': pa.int64(),
        'timestamp': pa.int64(),
        'message': pa.string(),
        'fingerprint': pa.int64(),
    }
    for name, expected_type in expected_types.items():
        actual_type = table.schema.field(name).type
        assert actual_type == expected_type, f'Column {name} must have type {expected_type}, got {actual_type}.'

    records = table.to_pylist()
    assert len(records) == 4, f'Expected exactly 4 deduplicated records in Parquet, found {len(records)}.'
    assert all(all(value is not None for value in record.values()) for record in records), \
        'Parquet output must not contain null field values.'

    user_timestamps = {int(r['user_id']): int(r['timestamp']) for r in records}
    expected_timestamps = {
        1: 1600000000,
        2: 1600000005,
        3: 1600000000,
        4: 1600000000,
    }
    for uid, expected_ts in expected_timestamps.items():
        assert uid in user_timestamps, f'User {uid} is missing from the Parquet file.'
        assert user_timestamps[uid] == expected_ts, \
            f'Expected timestamp {expected_ts} for user {uid}, got {user_timestamps[uid]}.'

    sort_key = lambda r: (r['user_id'], r['timestamp'], r['message'], r['fingerprint'])
    assert sorted(records, key=sort_key) == sorted(EXPECTED_RECORDS, key=sort_key), \
        f'Parquet records do not match the records derived from the raw files. Got: {records}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
