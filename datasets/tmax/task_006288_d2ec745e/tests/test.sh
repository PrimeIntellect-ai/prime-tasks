#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import re
import secrets
import stat
import subprocess
from datetime import datetime, timezone
from pathlib import Path

RAW = Path('/home/user/raw_data.jsonl')
INVALID = Path('/home/user/invalid_records.jsonl')
PROCESSED = Path('/home/user/processed_data.csv')
HEADER = ['user_id', 'ad_id', 'hour_of_day', 'clicks', 'impressions', 'bayesian_ctr']


def test_invalid_records_jsonl():
    assert INVALID.exists(), f'File {INVALID} is missing.'
    assert INVALID.is_file(), f'Path {INVALID} is not a file.'

    expected_invalid = [
        {'user_id': 102, 'ad_id': 502, 'clicks': '2', 'impressions': 50, 'timestamp': '2023-10-15T09:15:00Z'},
        {'user_id': 103, 'ad_id': 503, 'clicks': 10, 'impressions': 5, 'timestamp': '2023-10-15T14:00:00Z'},
        {'user_id': 101, 'ad_id': 506, 'clicks': -1, 'impressions': 10, 'timestamp': '2023-10-15T08:30:00Z'},
        {'user_id': 106, 'ad_id': 507, 'clicks': 2, 'impressions': 0, 'timestamp': '2023-10-15T11:00:00Z'},
        {'user_id': 107, 'ad_id': 508, 'clicks': 3, 'impressions': 50},
        {'user_id': 108, 'ad_id': 509, 'clicks': 15, 'impressions': 1000, 'timestamp': '2023-10-15T18:22:00Z', 'extra_field': True},
    ]

    lines = INVALID.read_text().strip().split('\n')
    actual_invalid = []
    for line in lines:
        if not line.strip():
            continue
        try:
            actual_invalid.append(json.loads(line))
        except json.JSONDecodeError:
            assert False, f'Line in {INVALID} is not valid JSON: {line}'

    assert len(actual_invalid) == len(expected_invalid), \
        f'Expected {len(expected_invalid)} invalid records, found {len(actual_invalid)}'
    for expected_record in expected_invalid:
        assert expected_record in actual_invalid, \
            f'Expected invalid record {expected_record} not found in {INVALID}'

    raw_lines = RAW.read_bytes().splitlines(keepends=True)
    expected_exact = b''.join(raw_lines[i] for i in [1, 2, 5, 6, 7, 8])
    assert INVALID.read_bytes() == expected_exact, \
        'Invalid records must be in input order and copied byte-for-byte exactly as they appeared.'


def test_processed_data_csv():
    assert PROCESSED.exists(), f'File {PROCESSED} is missing.'
    assert PROCESSED.is_file(), f'Path {PROCESSED} is not a file.'

    expected_rows = [
        ['101', '501', '8', '5', '100', '0.0347'],
        ['104', '504', '22', '0', '20', '0.0164'],
        ['105', '505', '0', '1', '10', '0.0268'],
        ['109', '510', '18', '15', '1000', '0.0154'],
    ]

    with PROCESSED.open('r', newline='') as f:
        rows = list(csv.reader(f))

    assert rows, f'{PROCESSED} is empty.'
    assert rows[0] == HEADER, f'Expected header {HEADER}, found {rows[0]}'
    actual_data = rows[1:]
    assert len(actual_data) == len(expected_rows), \
        f'Expected {len(expected_rows)} processed records, found {len(actual_data)}'
    for i, (actual_row, expected_row) in enumerate(zip(actual_data, expected_rows)):
        assert actual_row == expected_row, \
            f'Row {i+1} mismatch. Expected {expected_row}, found {actual_row}. Make sure data is sorted by user_id then ad_id.'


def candidate_commands():
    excluded = {RAW.resolve(), INVALID.resolve(), PROCESSED.resolve()}
    commands = []
    seen = set()
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in {'.cache', '__pycache__', '.git'}]
        for name in files:
            path = Path(root) / name
            try:
                resolved = path.resolve()
                info = path.stat()
            except OSError:
                continue
            if resolved in excluded or not stat.S_ISREG(info.st_mode) or info.st_size > 5_000_000:
                continue

            cmd = None
            if path.suffix.lower() == '.py':
                cmd = ['python3', str(path)]
            elif path.suffix.lower() in {'.sh', '.bash'}:
                cmd = ['bash', str(path)]
            else:
                try:
                    prefix = path.read_bytes()[:256]
                except OSError:
                    continue
                first = prefix.splitlines()[0].lower() if prefix else b''
                if first.startswith(b'#!') and b'python' in first:
                    cmd = ['python3', str(path)]
                elif first.startswith(b'#!') and any(x in first for x in (b'sh', b'bash')):
                    cmd = ['bash', str(path)]
                elif os.access(path, os.X_OK):
                    cmd = [str(path)]
                elif info.st_size < 1_000_000:
                    try:
                        source = path.read_text()
                        tree = ast.parse(source)
                        if tree.body:
                            cmd = ['python3', str(path)]
                    except (OSError, UnicodeError, SyntaxError):
                        pass

            if cmd is not None:
                key = tuple(cmd)
                if key not in seen:
                    seen.add(key)
                    commands.append(cmd)
    return commands


def strict_valid(record):
    required = {'user_id', 'ad_id', 'clicks', 'impressions', 'timestamp'}
    if not isinstance(record, dict) or set(record) != required:
        return False
    for key in ('user_id', 'ad_id', 'clicks', 'impressions'):
        if type(record[key]) is not int:
            return False
    if record['clicks'] < 0 or record['impressions'] <= 0 or record['clicks'] > record['impressions']:
        return False
    if type(record['timestamp']) is not str:
        return False
    if not re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z', record['timestamp']):
        return False
    try:
        datetime.strptime(record['timestamp'], '%Y-%m-%dT%H:%M:%SZ')
    except ValueError:
        return False
    return True


def expected_for_fixture(fixture):
    invalid_bytes = bytearray()
    valid = []
    for raw_line in fixture.splitlines(keepends=True):
        record = json.loads(raw_line)
        if not strict_valid(record):
            invalid_bytes.extend(raw_line)
            continue
        dt = datetime.strptime(record['timestamp'], '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
        valid.append([
            str(record['user_id']),
            str(record['ad_id']),
            str(dt.hour),
            str(record['clicks']),
            str(record['impressions']),
            f"{(record['clicks'] + 2) / (record['impressions'] + 102):.4f}",
        ])
    valid.sort(key=lambda row: (int(row[0]), int(row[1])))
    return bytes(invalid_bytes), valid


def outputs_match(expected_invalid, expected_rows):
    if not INVALID.is_file() or not PROCESSED.is_file():
        return False
    if INVALID.read_bytes() != expected_invalid:
        return False
    try:
        with PROCESSED.open('r', newline='') as f:
            rows = list(csv.reader(f))
    except Exception:
        return False
    return rows == [HEADER] + expected_rows


def test_pipeline_executes_on_unseen_input():
    commands = candidate_commands()
    assert commands, 'No executable ETL implementation was found under /home/user.'

    base = 200000 + secrets.randbelow(500000)
    records = [
        {'timestamp': '2026-07-04T23:17:31Z', 'impressions': 321, 'clicks': 17, 'ad_id': base + 81, 'user_id': base + 30},
        {'user_id': base + 10, 'ad_id': base + 90, 'clicks': 0, 'impressions': 7, 'timestamp': '2025-01-02T00:01:02Z'},
        {'user_id': base + 10, 'ad_id': base + 12, 'clicks': 19, 'impressions': 40, 'timestamp': '2024-12-31T08:59:59Z'},
        {'user_id': True, 'ad_id': base + 1, 'clicks': 1, 'impressions': 2, 'timestamp': '2025-02-03T04:05:06Z'},
        {'user_id': base + 4, 'ad_id': base + 2, 'clicks': '3', 'impressions': 20, 'timestamp': '2025-02-03T04:05:06Z'},
        {'user_id': base + 5, 'ad_id': base + 3, 'clicks': 8, 'impressions': 7, 'timestamp': '2025-02-03T04:05:06Z'},
        {'user_id': base + 6, 'ad_id': base + 4, 'clicks': 1, 'impressions': 20, 'timestamp': 'not-a-time'},
        {'user_id': base + 7, 'ad_id': base + 5, 'clicks': 1, 'impressions': 20, 'timestamp': '2025-02-03T04:05:06Z', 'extra': 0},
        {'user_id': base + 8, 'ad_id': base + 6, 'clicks': 1, 'impressions': 20},
    ]

    rendered = []
    for i, record in enumerate(records):
        if i % 3 == 0:
            text = json.dumps(record, separators=(', ', ' : '))
        elif i % 3 == 1:
            text = json.dumps(record, separators=(',', ':'))
        else:
            text = json.dumps(record)
        rendered.append(text.encode() + b'\n')
    fixture = b''.join(rendered)
    expected_invalid, expected_rows = expected_for_fixture(fixture)

    originals = {}
    for path in (RAW, INVALID, PROCESSED):
        originals[path] = path.read_bytes() if path.exists() and path.is_file() else None

    successes = []
    try:
        for cmd in commands:
            RAW.write_bytes(fixture)
            for output in (INVALID, PROCESSED):
                try:
                    output.unlink()
                except FileNotFoundError:
                    pass
            try:
                result = subprocess.run(
                    cmd,
                    cwd='/home/user',
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=15,
                    env={**os.environ, 'HOME': '/home/user'},
                )
            except (OSError, subprocess.TimeoutExpired):
                continue
            if result.returncode == 0 and outputs_match(expected_invalid, expected_rows):
                successes.append(cmd)
                break
    finally:
        for path, content in originals.items():
            if content is None:
                try:
                    path.unlink()
                except FileNotFoundError:
                    pass
            else:
                path.write_bytes(content)

    assert successes, \
        'No submitted ETL implementation successfully processed an unseen input fixture.'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
