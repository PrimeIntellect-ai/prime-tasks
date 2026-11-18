#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import sqlite3
import stat
import subprocess
import tempfile

SOURCE = '/home/user/pipeline/extractor.c'
EXTRACTOR = '/home/user/pipeline/extractor'
ALERTS = '/home/user/pipeline/alerts.csv'
ORIGINAL_DB = '/home/user/data/legacy_telemetry.db'
HEADER = ['device', 'timestamp', 'reading', 'moving_average']


def test_extractor_c_exists():
    path = SOURCE
    assert os.path.isfile(path), f"Source file {path} is missing."
    with open(path, 'r') as f:
        content = f.read()
        assert 'sqlite3_bind' in content, "The C source code does not appear to use sqlite3_bind_* for parameter binding."


def test_extractor_executable_exists():
    path = EXTRACTOR
    assert os.path.isfile(path), f"Executable {path} is missing."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."
    with open(path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"File {path} is not a compiled executable."


def make_test_database(path):
    conn = sqlite3.connect(path)
    conn.execute('''
        CREATE TABLE raw_telemetry (
            record_id INTEGER PRIMARY KEY,
            device_uid TEXT NOT NULL,
            recorded_at INTEGER NOT NULL,
            val REAL NOT NULL
        )
    ''')
    # Deliberately insert rows out of timestamp and device order.
    conn.executemany(
        'INSERT INTO raw_telemetry (device_uid, recorded_at, val) VALUES (?, ?, ?)',
        [
            ('ALPHA', 30, 90.0),
            ('BETA', 15, -20.0),
            ('ALPHA', 10, 10.0),
            ('BETA', 35, 20.0),
            ('ALPHA', 40, 80.0),
            ('BETA', 5, 100.0),
            ('ALPHA', 20, 50.0),
            ('BETA', 25, 80.0),
            ('GAMMA', 7, 53.33),
        ],
    )
    conn.commit()
    conn.close()


def derive_expected(records, threshold):
    by_device = {}
    for device, timestamp, reading in records:
        by_device.setdefault(device, []).append((timestamp, reading))

    expected = []
    for device, rows in by_device.items():
        rows.sort(key=lambda row: row[0])
        for index, (timestamp, reading) in enumerate(rows):
            window = rows[max(0, index - 2):index + 1]
            average = sum(value for _, value in window) / len(window)
            if average > threshold:
                expected.append({
                    'device': device,
                    'timestamp': str(timestamp),
                    'reading': f'{reading:.2f}',
                    'moving_average': f'{average:.2f}',
                })
    expected.sort(key=lambda row: (row['device'], int(row['timestamp'])))
    return expected


def read_alerts():
    assert os.path.isfile(ALERTS), f"Output file {ALERTS} was not created."
    with open(ALERTS, 'r', newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == HEADER, 'CSV header is incorrect.'
        rows = list(reader)
    for row in rows:
        assert set(row) == set(HEADER), f'CSV row has incorrect columns: {row}'
    rows.sort(key=lambda row: (row['device'], int(row['timestamp'])))
    return rows


def run_and_check(executable, db_path, threshold, records):
    if os.path.exists(ALERTS):
        os.remove(ALERTS)
    result = subprocess.run(
        [executable, db_path, str(threshold)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f'Extractor failed for threshold {threshold}: {result.stderr}'
    )
    actual = read_alerts()
    expected = derive_expected(records, threshold)
    assert actual == expected, (
        f'Incorrect output for threshold {threshold}. Expected {expected}, got {actual}.'
    )


def test_extractor_behavior_and_arguments():
    rebuilt = '/tmp/extractor_rebuilt'
    compile_result = subprocess.run(
        ['gcc', SOURCE, '-o', rebuilt, '-lsqlite3', '-lm'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f'extractor.c does not compile: {compile_result.stderr}'
    )

    symbols = subprocess.run(
        ['nm', '-D', rebuilt], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10
    )
    assert symbols.returncode == 0
    assert 'sqlite3_bind_' in symbols.stdout, (
        'The compiled source does not reference a sqlite3_bind_* API.'
    )

    records = [
        ('ALPHA', 30, 90.0), ('BETA', 15, -20.0),
        ('ALPHA', 10, 10.0), ('BETA', 35, 20.0),
        ('ALPHA', 40, 80.0), ('BETA', 5, 100.0),
        ('ALPHA', 20, 50.0), ('BETA', 25, 80.0),
        ('GAMMA', 7, 53.33),
    ]

    fd, db_path = tempfile.mkstemp(suffix='.db')
    os.close(fd)
    os.unlink(db_path)
    make_test_database(db_path)

    try:
        for executable in (EXTRACTOR, rebuilt):
            for args in ([], [db_path], [db_path, '50.0', 'extra']):
                result = subprocess.run(
                    [executable] + args,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=10,
                )
                assert result.returncode != 0, (
                    f'{executable} must reject an argument count other than two.'
                )

            for threshold in (30.0, 50.0, 53.33, 100.0):
                run_and_check(executable, db_path, threshold, records)
    finally:
        if os.path.exists(db_path):
            os.remove(db_path)
        # Leave alerts.csv in the state required by the instruction.
        restore = subprocess.run(
            [EXTRACTOR, ORIGINAL_DB, '50.00'],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert restore.returncode == 0, (
            f'Could not run extractor on the required database: {restore.stderr}'
        )


def test_alerts_csv_content():
    db_path = ORIGINAL_DB
    csv_path = ALERTS

    assert os.path.isfile(csv_path), f"Output file {csv_path} is missing."

    # Compute expected truth from the database
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    query = """
    WITH MovingAvgs AS (
        SELECT
            device_uid,
            recorded_at,
            val,
            AVG(val) OVER (
                PARTITION BY device_uid
                ORDER BY recorded_at
                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
            ) as m_avg
        FROM raw_telemetry
    )
    SELECT device_uid, recorded_at, val, m_avg FROM MovingAvgs WHERE m_avg > 50.0;
    """
    cursor.execute(query)
    expected_rows = cursor.fetchall()
    conn.close()

    expected_data = []
    for row in expected_rows:
        expected_data.append({
            'device': str(row[0]),
            'timestamp': str(row[1]),
            'reading': f"{row[2]:.2f}",
            'moving_average': f"{row[3]:.2f}"
        })

    expected_data.sort(key=lambda x: (x['device'], int(x['timestamp'])))

    actual_data = []
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == HEADER, "CSV header is incorrect."
        for row in reader:
            actual_data.append(row)

    actual_data.sort(key=lambda x: (x['device'], int(x['timestamp'])))

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} rows in CSV, found {len(actual_data)}."

    for actual, expected in zip(actual_data, expected_data):
        assert actual == expected, f"Row mismatch. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
