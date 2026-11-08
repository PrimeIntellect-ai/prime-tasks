#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import re
from collections import Counter
from datetime import datetime

RAW_PATH = '/home/user/raw_logs.csv'
SOURCE_PATH = '/var/www/raw_logs.csv'
CLEAN_PATH = '/home/user/clean_logs.csv'
COUNTS_PATH = '/home/user/status_counts.txt'
VALID_STATUSES = {'200', '301', '404', '500'}


def expected_clean_rows():
    with open(SOURCE_PATH, 'rb') as f:
        decoded = f.read().decode('utf-8', errors='ignore')

    rows = list(csv.reader(io.StringIO(decoded, newline='')))
    assert rows and rows[0] == ['id', 'timestamp', 'status', 'message'], 'Source CSV header is invalid'

    expected = [rows[0]]
    for row in rows[1:]:
        assert len(row) == 4, f'Unexpected source CSV row: {row!r}'
        if row[2] not in VALID_STATUSES:
            continue
        timestamp = datetime.strptime(row[1], '%m/%d/%Y %H:%M:%S').strftime('%Y-%m-%d %H:%M:%S')
        message = row[3].replace('\r\n', ' ').replace('\r', ' ').replace('\n', ' ')
        expected.append([row[0], timestamp, row[2], message])
    return expected


def read_clean_rows():
    with open(CLEAN_PATH, 'r', encoding='utf-8', newline='') as f:
        return list(csv.reader(f))


def test_raw_logs_downloaded():
    assert os.path.isfile(RAW_PATH), 'raw_logs.csv was not downloaded to /home/user/'
    with open(RAW_PATH, 'rb') as downloaded, open(SOURCE_PATH, 'rb') as source:
        assert downloaded.read() == source.read(), 'Downloaded raw_logs.csv does not match the served input'


def test_clean_logs_exists_and_utf8():
    assert os.path.isfile(CLEAN_PATH), 'clean_logs.csv is missing'
    try:
        with open(CLEAN_PATH, 'r', encoding='utf-8') as f:
            f.read()
    except UnicodeDecodeError:
        assert False, 'clean_logs.csv contains invalid UTF-8 characters'


def test_clean_logs_content():
    assert os.path.isfile(CLEAN_PATH), 'clean_logs.csv is missing'

    with open(CLEAN_PATH, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 6, f'Expected exactly 6 lines (1 header + 5 rows), found {len(lines)}'
    assert lines[0] == 'id,timestamp,status,message', 'Header row is missing or incorrect'

    for line in lines[1:]:
        parts = line.split(',', 3)
        assert len(parts) == 4, f'Line does not have 4 columns: {line}'
        timestamp = parts[1]
        assert re.match(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$', timestamp), \
            f'Timestamp {timestamp} is not in YYYY-MM-DD HH:MM:SS format'
        status = parts[2]
        assert status in VALID_STATUSES, f'Found invalid status {status} in clean_logs.csv'
        message = parts[3]
        assert message.startswith('"') and message.endswith('"'), \
            f'Message field not properly quoted: {message}'
        assert '\n' not in message, 'Embedded newline was not removed'

    actual_rows = read_clean_rows()
    expected_rows = expected_clean_rows()
    assert actual_rows == expected_rows, \
        f'clean_logs.csv does not contain the correctly transformed source records.\nExpected: {expected_rows!r}\nGot: {actual_rows!r}'


def test_status_counts():
    assert os.path.isfile(COUNTS_PATH), 'status_counts.txt is missing'

    with open(COUNTS_PATH, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    expected = (
        '200: 2\n'
        '301: 1\n'
        '404: 1\n'
        '500: 1'
    )
    assert content == expected, \
        f'status_counts.txt content is incorrect.\nExpected:\n{expected}\nGot:\n{content}'

    clean_rows = read_clean_rows()
    assert clean_rows and clean_rows[0] == ['id', 'timestamp', 'status', 'message']
    counts = Counter(row[2] for row in clean_rows[1:])
    derived = '\n'.join(f'{status}: {counts[status]}' for status in sorted(counts, key=int))
    assert content == derived, \
        f'status_counts.txt was not computed from clean_logs.csv.\nExpected from cleaned data:\n{derived}\nGot:\n{content}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
