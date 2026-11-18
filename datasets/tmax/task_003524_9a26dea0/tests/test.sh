#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_etl.py
import ast
import csv
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from collections import defaultdict
from datetime import datetime, timezone

SCRIPT = '/home/user/etl_job.py'
INBOX = '/home/user/remote_inbox'
OUTPUT = '/home/user/output/clean_aggregates.csv'
HEADERS = ['sensor_id', 'timestamp_utc', 'temp_rolling_avg']
TS_RE = re.compile(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$')
AVG_RE = re.compile(r'^-?\d+\.\d{2}$')

BASE = {
    'alpha': [
        ('2023-10-01T10:00:00Z', 20.0),
        ('2023-10-01T10:05:00Z', 21.5),
        ('2023-10-01T10:05:00Z', 21.5),
        ('2023-10-01T10:10:00Z', 22.0),
        ('2023-10-01T10:15:00Z', 21.0),
        ('2023-10-01T10:15:00Z', 21.0),
    ],
    'beta': [
        ('1696154400', 15.0),
        ('1696154700', 16.0),
        ('1696155000', 15.5),
        ('1696154400', 15.0),
        ('1696155300', 17.0),
    ],
    'gamma': [
        ('01-10-2023 10:00:00', 30.0),
        ('01-10-2023 10:05:00', 31.0),
        ('01-10-2023 10:10:00', 30.5),
        ('01-10-2023 10:05:00', 31.0),
    ],
}


def check_script_and_parallelism():
    assert os.path.isfile(SCRIPT), f'Missing required script: {SCRIPT}'
    assert not os.path.islink(SCRIPT), 'etl_job.py must be a regular Python source file, not a symlink'
    with open(SCRIPT, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT)

    imported = False
    constructors = False
    operation = False
    constructor_names = {'Pool', 'ThreadPool', 'Process', 'ProcessPoolExecutor', 'ThreadPoolExecutor'}
    operation_names = {'map', 'starmap', 'imap', 'imap_unordered', 'apply_async', 'submit', 'start'}

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            if any(a.name == 'multiprocessing' or a.name.startswith('multiprocessing.') or
                   a.name == 'concurrent.futures' for a in node.names):
                imported = True
        elif isinstance(node, ast.ImportFrom):
            if node.module and (node.module == 'multiprocessing' or
                                node.module.startswith('multiprocessing.') or
                                node.module == 'concurrent.futures'):
                imported = True
        elif isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Name) and func.id in constructor_names:
                constructors = True
            elif isinstance(func, ast.Attribute):
                if func.attr in constructor_names:
                    constructors = True
                if func.attr in operation_names:
                    operation = True

    assert imported and constructors and operation, (
        'etl_job.py must use multiprocessing or concurrent.futures to process files in parallel'
    )


def write_fixture(offsets):
    os.makedirs(INBOX, exist_ok=True)
    for name in os.listdir(INBOX):
        path = os.path.join(INBOX, name)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)

    settings = {
        'alpha': ('sensor_alpha.csv', 'utf-8'),
        'beta': ('sensor_beta.csv', 'utf-16'),
        'gamma': ('sensor_gamma.csv', 'iso-8859-1'),
    }
    for sensor, rows in BASE.items():
        filename, encoding = settings[sensor]
        with open(os.path.join(INBOX, filename), 'w', newline='', encoding=encoding) as f:
            writer = csv.writer(f)
            writer.writerow(['sensor_id', 'timestamp', 'temperature'])
            for timestamp, temperature in rows:
                writer.writerow([sensor, timestamp, f'{temperature + offsets[sensor]:.1f}'])


def parse_timestamp(sensor, value):
    if sensor == 'alpha':
        return datetime.strptime(value, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
    if sensor == 'beta':
        return datetime.fromtimestamp(int(value), tz=timezone.utc)
    if sensor == 'gamma':
        return datetime.strptime(value, '%d-%m-%Y %H:%M:%S').replace(tzinfo=timezone.utc)
    raise AssertionError(f'Unexpected sensor {sensor!r}')


def derive_expected_from_inputs():
    files = [
        ('sensor_alpha.csv', 'utf-8'),
        ('sensor_beta.csv', 'utf-16'),
        ('sensor_gamma.csv', 'iso-8859-1'),
    ]
    deduplicated = {}
    for filename, encoding in files:
        with open(os.path.join(INBOX, filename), 'r', newline='', encoding=encoding) as f:
            reader = csv.DictReader(f)
            assert reader.fieldnames == ['sensor_id', 'timestamp', 'temperature']
            for row in reader:
                sensor = row['sensor_id']
                timestamp = parse_timestamp(sensor, row['timestamp'])
                key = (sensor, timestamp)
                temperature = float(row['temperature'])
                if key in deduplicated:
                    assert deduplicated[key] == temperature, 'Fixture contains a conflicting duplicate'
                else:
                    deduplicated[key] = temperature

    grouped = defaultdict(list)
    for (sensor, timestamp), temperature in deduplicated.items():
        grouped[sensor].append((timestamp, temperature))

    expected = []
    for sensor in sorted(grouped):
        history = []
        for timestamp, temperature in sorted(grouped[sensor]):
            history.append(temperature)
            rolling = sum(history[-3:]) / len(history[-3:])
            expected.append([
                sensor,
                timestamp.strftime('%Y-%m-%d %H:%M:%S'),
                f'{rolling:.2f}',
            ])
    return expected


def run_script(remove_output):
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    if remove_output and os.path.lexists(OUTPUT):
        if os.path.isdir(OUTPUT) and not os.path.islink(OUTPUT):
            shutil.rmtree(OUTPUT)
        else:
            os.unlink(OUTPUT)
    result = subprocess.run(
        ['python3', SCRIPT], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45
    )
    assert result.returncode == 0, f'etl_job.py failed with exit {result.returncode}:\n{result.stdout}'
    assert os.path.isfile(OUTPUT), f'Output file {OUTPUT} was not generated'
    with open(OUTPUT, 'rb') as f:
        return f.read()


def validate_output(expected, canonical=False):
    with open(OUTPUT, 'r', newline='', encoding='utf-8') as f:
        raw_rows = list(csv.reader(f))
    assert raw_rows, 'Output CSV is empty'
    assert raw_rows[0] == HEADERS, f'Headers do not match. Expected {HEADERS}, got {raw_rows[0]}'
    rows = raw_rows[1:]
    assert all(len(row) == 3 for row in rows), 'Every output row must have exactly three columns'
    assert rows == sorted(rows, key=lambda x: (x[0], x[1])), (
        'The output CSV is not sorted by sensor_id and timestamp_utc'
    )

    for row in rows:
        assert TS_RE.fullmatch(row[1]), f'Timestamp {row[1]} is not in %Y-%m-%d %H:%M:%S format'
        datetime.strptime(row[1], '%Y-%m-%d %H:%M:%S')
        assert '.' in row[2] and len(row[2].split('.')[1]) <= 2, (
            f'Value {row[2]} is not rounded to 2 decimal places'
        )
        assert AVG_RE.fullmatch(row[2]), f'Value {row[2]} is not formatted to exactly 2 decimal places'

    assert rows == expected, 'Output does not match the complete deduplicated rolling-average dataset'

    if canonical:
        assert len(rows) == 11, f'Expected exactly 11 deduplicated records, got {len(rows)}'
        lookup = {(r[0], r[1]): r[2] for r in rows}
        assert lookup.get(('alpha', '2023-10-01 10:10:00')) == '21.17'
        assert lookup.get(('beta', '2023-10-01 10:15:00')) == '16.17'
        assert lookup.get(('gamma', '2023-10-01 10:05:00')) in ('30.5', '30.50')


def exercise(offsets, canonical=False):
    write_fixture(offsets)
    expected = derive_expected_from_inputs()
    first = run_script(remove_output=True)
    validate_output(expected, canonical=canonical)
    second = run_script(remove_output=False)
    validate_output(expected, canonical=canonical)
    assert second == first, 'Running the ETL job twice changed or appended to the output'


def main():
    check_script_and_parallelism()
    backup_root = tempfile.mkdtemp(prefix='etl-inbox-backup-')
    backup = os.path.join(backup_root, 'remote_inbox')
    if os.path.exists(INBOX):
        shutil.copytree(INBOX, backup)
    try:
        exercise({'alpha': 0.0, 'beta': 0.0, 'gamma': 0.0}, canonical=True)
        # A per-run unpredictable fixture prevents a precomputed 11-row CSV from passing.
        offsets = {
            'alpha': (secrets.randbelow(151) + 17) / 10.0,
            'beta': -(secrets.randbelow(91) + 13) / 10.0,
            'gamma': (secrets.randbelow(121) + 23) / 10.0,
        }
        exercise(offsets, canonical=False)
    finally:
        if os.path.exists(INBOX):
            shutil.rmtree(INBOX)
        if os.path.exists(backup):
            shutil.copytree(backup, INBOX)
        else:
            os.makedirs(INBOX, exist_ok=True)
        shutil.rmtree(backup_root, ignore_errors=True)


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_etl.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
