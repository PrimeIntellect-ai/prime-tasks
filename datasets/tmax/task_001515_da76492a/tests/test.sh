#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
from collections import defaultdict
from datetime import datetime, timedelta

PROCESSED_CSV = '/home/user/processed_logs.csv'
REPORT_MD = '/home/user/report.md'
RAW_CSV = '/home/user/raw_logs.csv'

CANONICAL_RAW = '''timestamp,app_server,db_server,web_server
2023-10-01 10:15:00,"Started process
[INFO] All good","[ERROR] Timeout
Retrying","[INFO] Serving traffic"
2023-10-01 10:45:00,"[ERROR] Failed to fetch",,
2023-10-01 12:05:00,"[ERROR] Crash
Dump saved",,"[ERROR] 500 Internal"
2023-10-01 14:30:00,"[INFO] Restarted",,
'''

SERVICE_MAP = {
    'app_server': 'APP',
    'db_server': 'DB',
    'web_server': 'WEB',
}
SERVICES = ['APP', 'DB', 'WEB']
TIME_FORMAT = '%Y-%m-%d %H:%M:%S'


def derive_expected():
    with open(RAW_CSV, 'r', encoding='utf-8', newline='') as f:
        raw_text = f.read()
    assert raw_text == CANONICAL_RAW, 'The provided raw input was modified.'

    grouped = defaultdict(list)
    populated_hours = []
    for raw_row in csv.DictReader(io.StringIO(CANONICAL_RAW, newline='')):
        timestamp = datetime.strptime(raw_row['timestamp'], TIME_FORMAT)
        hour = timestamp.replace(minute=0, second=0, microsecond=0)
        for source_name, service in SERVICE_MAP.items():
            message = raw_row[source_name]
            if message is None or message == '':
                continue
            message = message.replace('\r\n', ' ').replace('\n', ' ').replace('\r', ' ').strip()
            grouped[(service, hour)].append(message)
            populated_hours.append(hour)

    minimum = min(populated_hours)
    maximum = max(populated_hours)
    hours = []
    current = minimum
    while current <= maximum:
        hours.append(current)
        current += timedelta(hours=1)

    expected = []
    for service in SERVICES:
        indicators = []
        for hour in hours:
            messages = grouped.get((service, hour), [])
            message = ' | '.join(messages) if messages else 'NO_DATA'
            indicators.append(1 if 'ERROR' in message else 0)
            rolling = sum(indicators[-3:])
            expected.append({
                'timestamp': hour.strftime(TIME_FORMAT),
                'service': service,
                'message': message,
                'error_count_3h': rolling,
            })
    return expected


def read_processed():
    with open(PROCESSED_CSV, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['timestamp', 'service', 'message', 'error_count_3h'], \
            f'Unexpected header in processed CSV: {reader.fieldnames}'
        rows = list(reader)
    return rows


def test_files_exist():
    assert os.path.isfile(PROCESSED_CSV), f'Processed CSV not found at {PROCESSED_CSV}'
    assert os.path.isfile(REPORT_MD), f'Report markdown not found at {REPORT_MD}'


def test_processed_csv_structure_and_sorting():
    rows = read_processed()
    assert len(rows) == 15, f'Expected 15 rows in processed CSV, found {len(rows)}'

    services = [row['service'] for row in rows]
    assert services == sorted(services), 'CSV is not sorted by service ascending.'
    for service in SERVICES:
        service_times = [row['timestamp'] for row in rows if row['service'] == service]
        assert service_times == sorted(service_times), \
            f'CSV is not sorted by timestamp ascending for service {service}.'


def test_processed_csv_content_complete():
    actual = read_processed()
    expected = derive_expected()

    assert len(actual) == len(expected)
    for index, (actual_row, expected_row) in enumerate(zip(actual, expected), start=2):
        assert set(actual_row) == {'timestamp', 'service', 'message', 'error_count_3h'}
        assert actual_row['timestamp'] == expected_row['timestamp'], f'Wrong timestamp on CSV line {index}'
        assert actual_row['service'] == expected_row['service'], f'Wrong service on CSV line {index}'
        assert actual_row['message'] == expected_row['message'], f'Wrong message on CSV line {index}'
        try:
            count = float(actual_row['error_count_3h'])
        except (TypeError, ValueError):
            raise AssertionError(f'Invalid error_count_3h on CSV line {index}')
        assert count == float(expected_row['error_count_3h']), \
            f'Wrong error_count_3h on CSV line {index}'

    by_key = {(row['service'], row['timestamp']): row for row in actual}
    assert len(by_key) == 15, 'Duplicate service/timestamp rows found.'

    # Preserve the original spot checks, corrected for the real APP log at 14:30.
    assert by_key[('APP', '2023-10-01 10:00:00')]['message'] == \
        'Started process [INFO] All good | [ERROR] Failed to fetch'
    assert float(by_key[('APP', '2023-10-01 10:00:00')]['error_count_3h']) == 1.0
    assert by_key[('APP', '2023-10-01 12:00:00')]['message'] == '[ERROR] Crash Dump saved'
    assert float(by_key[('APP', '2023-10-01 12:00:00')]['error_count_3h']) == 2.0
    assert by_key[('DB', '2023-10-01 10:00:00')]['message'] == '[ERROR] Timeout Retrying'
    assert float(by_key[('DB', '2023-10-01 10:00:00')]['error_count_3h']) == 1.0
    assert by_key[('WEB', '2023-10-01 12:00:00')]['message'] == '[ERROR] 500 Internal'
    assert float(by_key[('WEB', '2023-10-01 12:00:00')]['error_count_3h']) == 1.0
    assert by_key[('APP', '2023-10-01 11:00:00')]['message'] == 'NO_DATA'
    assert float(by_key[('APP', '2023-10-01 11:00:00')]['error_count_3h']) == 1.0
    assert by_key[('APP', '2023-10-01 13:00:00')]['message'] == 'NO_DATA'
    assert float(by_key[('APP', '2023-10-01 13:00:00')]['error_count_3h']) == 1.0
    assert by_key[('APP', '2023-10-01 14:00:00')]['message'] == '[INFO] Restarted'
    assert float(by_key[('APP', '2023-10-01 14:00:00')]['error_count_3h']) == 0.0


def test_report_content():
    expected_rows = derive_expected()
    expected_max = {}
    expected_latest = {}
    for service in SERVICES:
        service_rows = [row for row in expected_rows if row['service'] == service]
        expected_max[service] = max(row['error_count_3h'] for row in service_rows)
        expected_latest[service] = service_rows[-1]['message']

    with open(REPORT_MD, 'r', encoding='utf-8') as f:
        lines = f.read().splitlines()

    assert lines == [
        '# Service Report',
        '',
        '## APP',
        lines[3] if len(lines) > 3 else '',
        f"Latest Message: {expected_latest['APP']}",
        '',
        '## DB',
        lines[7] if len(lines) > 7 else '',
        f"Latest Message: {expected_latest['DB']}",
        '',
        '## WEB',
        lines[11] if len(lines) > 11 else '',
        f"Latest Message: {expected_latest['WEB']}",
    ], 'Report does not exactly follow the required template or has incorrect latest messages.'

    for service, line_index in [('APP', 3), ('DB', 7), ('WEB', 11)]:
        prefix = 'Max 3H Errors: '
        assert lines[line_index].startswith(prefix), f'Invalid Max 3H Errors line for {service}'
        value = lines[line_index][len(prefix):]
        try:
            numeric_value = float(value)
        except ValueError:
            raise AssertionError(f'Invalid Max 3H Errors value for {service}')
        assert numeric_value == float(expected_max[service]), f'Wrong Max 3H Errors for {service}'

    assert expected_max == {'APP': 2, 'DB': 1, 'WEB': 1}
    assert expected_latest == {'APP': '[INFO] Restarted', 'DB': 'NO_DATA', 'WEB': 'NO_DATA'}
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
