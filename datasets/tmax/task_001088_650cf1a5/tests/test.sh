#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/verify_etl.py
import csv
import datetime
import json
import os
import secrets
import sqlite3
import subprocess
from collections import defaultdict
from decimal import Decimal

SCRIPT = '/home/user/process.py'
RAW = '/home/user/raw_sensors.jsonl'
CSV_PATH = '/home/user/aggregated.csv'
DB_PATH = '/home/user/sensor_data.db'


def run_script():
    for path in (CSV_PATH, DB_PATH):
        if os.path.lexists(path):
            if os.path.isdir(path):
                raise AssertionError(f'{path} must not be a directory')
            os.unlink(path)
    subprocess.run(['python3', SCRIPT], check=True, timeout=30)


def read_csv():
    assert os.path.exists(CSV_PATH), f'CSV file {CSV_PATH} is missing.'
    assert os.path.isfile(CSV_PATH), f'Path {CSV_PATH} is not a file.'
    with open(CSV_PATH, 'r', newline='') as f:
        rows = list(csv.reader(f))
    assert len(rows) > 0, 'CSV file is empty.'
    assert rows[0] == ['sensor_name', 'bucket_time', 'avg_value'], f'Incorrect CSV header: {rows[0]}'
    return rows[1:]


def read_db():
    assert os.path.exists(DB_PATH), f'SQLite database {DB_PATH} is missing.'
    assert os.path.isfile(DB_PATH), f'Path {DB_PATH} is not a file.'
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='hourly_aggregates'")
        assert cursor.fetchone() is not None, "Table 'hourly_aggregates' does not exist in the database."
        cursor.execute('PRAGMA table_info(hourly_aggregates)')
        columns = {row[1]: row[2].upper() for row in cursor.fetchall()}
        assert 'sensor_name' in columns, "Column 'sensor_name' missing."
        assert 'TEXT' in columns['sensor_name'], f"Column 'sensor_name' should be TEXT, got {columns['sensor_name']}."
        assert 'bucket_time' in columns, "Column 'bucket_time' missing."
        assert 'INT' in columns['bucket_time'], f"Column 'bucket_time' should be INTEGER, got {columns['bucket_time']}."
        assert 'avg_value' in columns, "Column 'avg_value' missing."
        assert ('REAL' in columns['avg_value'] or 'NUM' in columns['avg_value'] or
                'FLOAT' in columns['avg_value']), f"Column 'avg_value' should be REAL, got {columns['avg_value']}."
        cursor.execute('SELECT sensor_name, bucket_time, avg_value FROM hourly_aggregates ORDER BY sensor_name ASC, bucket_time ASC')
        return cursor.fetchall()
    finally:
        conn.close()


def assert_original_outputs():
    data_rows = read_csv()
    assert len(data_rows) == 3, f'Expected 3 data rows, got {len(data_rows)}.'
    assert data_rows[0][0] == 'humidity_b', f'Row 1 sensor_name wrong: {data_rows[0][0]}'
    assert data_rows[0][1] == '1672574400', f'Row 1 bucket_time wrong: {data_rows[0][1]}'
    assert float(data_rows[0][2]) == 45.0, f'Row 1 avg_value wrong: {data_rows[0][2]}'
    assert data_rows[1][0] == 'temp_a', f'Row 2 sensor_name wrong: {data_rows[1][0]}'
    assert data_rows[1][1] == '1672574400', f'Row 2 bucket_time wrong: {data_rows[1][1]}'
    assert float(data_rows[1][2]) == 23.5, f'Row 2 avg_value wrong: {data_rows[1][2]}'
    assert data_rows[2][0] == 'temp_a', f'Row 3 sensor_name wrong: {data_rows[2][0]}'
    assert data_rows[2][1] == '1672578000', f'Row 3 bucket_time wrong: {data_rows[2][1]}'
    assert float(data_rows[2][2]) == 25.0, f'Row 3 avg_value wrong: {data_rows[2][2]}'

    db_rows = read_db()
    assert len(db_rows) == 3, f'Expected 3 rows in database, got {len(db_rows)}.'
    assert db_rows[0][0] == 'humidity_b'
    assert int(db_rows[0][1]) == 1672574400
    assert float(db_rows[0][2]) == 45.0
    assert db_rows[1][0] == 'temp_a'
    assert int(db_rows[1][1]) == 1672574400
    assert float(db_rows[1][2]) == 23.5
    assert db_rows[2][0] == 'temp_a'
    assert int(db_rows[2][1]) == 1672578000
    assert float(db_rows[2][2]) == 25.0


def iso(epoch):
    return datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def make_challenge():
    base = ((1600000000 + secrets.randbelow(180000000)) // 3600) * 3600
    suffix = secrets.token_hex(4)
    n = secrets.randbelow(50) + 10
    sensor1 = f'Flow Meter {suffix}'
    sensor2 = f'Pressure Zone {suffix}'
    records = [
        {'sensor': sensor1, 'time': iso(base + 73), 'value': n + 0.111},
        {'sensor': sensor1.upper(), 'time': base + 73, 'value': 9999.0},
        {'sensor': sensor1.lower(), 'time': (base + 811) * 1000, 'value': n + 0.456},
        {'sensor': sensor1, 'time': base + 1703, 'value': n + 0.789},
        {'sensor': sensor2, 'time': base + 3600 + 11, 'value': n + 3.124},
        {'sensor': sensor2.lower(), 'time': iso(base + 3600 + 11), 'value': -5000.0},
        {'sensor': sensor2.upper(), 'time': (base + 3600 + 2500) * 1000, 'value': n + 3.568},
    ]
    with open(RAW, 'w') as f:
        for record in records:
            f.write(json.dumps(record) + '\n')


def normalized_time(value):
    if isinstance(value, str):
        return int(datetime.datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp())
    value = int(value)
    return value // 1000 if abs(value) >= 100000000000 else value


def derive_expected():
    seen = set()
    groups = defaultdict(list)
    with open(RAW) as f:
        for line in f:
            record = json.loads(line)
            name = record['sensor'].lower().replace(' ', '_')
            epoch = normalized_time(record['time'])
            key = (name, epoch)
            if key in seen:
                continue
            seen.add(key)
            groups[(name, (epoch // 3600) * 3600)].append(float(record['value']))
    return [(name, bucket, sum(values) / len(values))
            for (name, bucket), values in sorted(groups.items())]


def assert_challenge_outputs():
    expected = derive_expected()
    csv_rows = read_csv()
    assert len(csv_rows) == len(expected), f'Expected {len(expected)} challenge CSV rows, got {len(csv_rows)}.'
    for actual, wanted in zip(csv_rows, expected):
        name, bucket, average = wanted
        assert actual[0] == name
        assert actual[1] == str(bucket)
        number = Decimal(actual[2])
        rounded = Decimal(str(average)).quantize(Decimal('0.01'))
        assert number == rounded, f'CSV average {actual[2]} is not the required rounded value {rounded}'
        assert number.as_tuple().exponent >= -2, f'CSV average {actual[2]} has more than two decimal places'

    db_rows = read_db()
    assert len(db_rows) == len(expected), f'Expected {len(expected)} challenge database rows, got {len(db_rows)}.'
    for actual, wanted in zip(db_rows, expected):
        name, bucket, average = wanted
        assert actual[0] == name
        assert int(actual[1]) == bucket
        assert abs(float(actual[2]) - average) < 1e-9


def main():
    assert os.path.exists(SCRIPT), f'Required script {SCRIPT} is missing.'
    assert os.path.isfile(SCRIPT), f'Path {SCRIPT} is not a regular file.'
    with open(RAW, 'rb') as f:
        original_raw = f.read()
    try:
        run_script()
        assert_original_outputs()
        make_challenge()
        run_script()
        assert_challenge_outputs()
    finally:
        with open(RAW, 'wb') as f:
            f.write(original_raw)
        if os.path.isfile(SCRIPT):
            try:
                run_script()
            except Exception:
                pass


if __name__ == '__main__':
    main()
PY

if python3 /tmp/verify_etl.py 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
