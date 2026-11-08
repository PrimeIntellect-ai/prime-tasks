#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime as dt
import os
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile
from collections import defaultdict

import pytest


def test_pipeline_log():
    log_path = '/home/user/pipeline.log'
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, 'r') as f:
        log_content = f.read()

    assert "Successfully processed 6 total rows" in log_content, \
        "The log file does not contain the expected success message with the correct row count."


def test_pipeline_cron():
    cron_path = '/home/user/pipeline.cron'
    assert os.path.isfile(cron_path), f"Cron file {cron_path} does not exist."

    with open(cron_path, 'r') as f:
        cron_content = f.read()

    assert "15 * * * *" in cron_content, "The cron file does not schedule the job at minute 15 of every hour."
    assert "/usr/bin/python3" in cron_content and "/home/user/process_pipeline.py" in cron_content, \
        "The cron file does not contain the correct command to execute the pipeline."


def test_database_aggregates():
    db_path = '/home/user/metrics.db'
    assert os.path.isfile(db_path), f"Database file {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='hourly_aggregates'")
    assert cursor.fetchone() is not None, "Table 'hourly_aggregates' does not exist in the database."

    cursor.execute("SELECT sensor_id, hour_bucket, avg_reading FROM hourly_aggregates ORDER BY sensor_id, hour_bucket")
    rows = cursor.fetchall()

    expected = [
        ('1', '2023-01-01 00:00:00', 15.0),
        ('1', '2023-01-01 01:00:00', 30.0),
        ('2', '2023-01-01 00:00:00', 100.0),
        ('2', '2023-01-01 01:00:00', 200.0)
    ]

    assert rows == expected, f"Database aggregates do not match the expected values. Got: {rows}"
    conn.close()


def test_script_executes_on_new_inputs():
    script_path = '/home/user/process_pipeline.py'
    incoming = '/home/user/incoming_data'
    db_path = '/home/user/metrics.db'
    log_path = '/home/user/pipeline.log'

    assert os.path.exists(script_path), f"Pipeline script {script_path} does not exist."
    assert stat.S_ISREG(os.stat(script_path).st_mode), f"{script_path} is not a regular file."
    assert os.path.getsize(script_path) > 0, f"Pipeline script {script_path} is empty."

    rng = secrets.SystemRandom()
    base = dt.datetime(2024, 1, 1, tzinfo=dt.timezone.utc) + dt.timedelta(
        days=rng.randrange(0, 300), hours=rng.randrange(1, 21)
    )
    readings = [float(rng.randrange(1, 500)) for _ in range(7)]

    sensor_1 = [
        (base + dt.timedelta(minutes=10), readings[0]),
        (base + dt.timedelta(minutes=35), readings[1]),
        (base + dt.timedelta(hours=1, minutes=5), readings[2]),
    ]
    sensor_2 = [
        (base - dt.timedelta(hours=1) + dt.timedelta(minutes=50), readings[3]),
        (base + dt.timedelta(minutes=15), readings[4]),
        (base + dt.timedelta(minutes=45), readings[5]),
        (base + dt.timedelta(hours=2, minutes=20), readings[6]),
    ]

    grouped = defaultdict(list)
    for sensor_id, records in [('1', sensor_1), ('2', sensor_2)]:
        for timestamp, reading in records:
            bucket = timestamp.replace(minute=0, second=0, microsecond=0).strftime('%Y-%m-%d %H:%M:%S')
            grouped[(sensor_id, bucket)].append(reading)
    expected = [
        (sensor_id, bucket, sum(values) / len(values))
        for (sensor_id, bucket), values in sorted(grouped.items())
    ]

    old_log = open(log_path, 'rb').read()
    backup_root = tempfile.mkdtemp(prefix='pipeline-input-backup-')
    backup_incoming = os.path.join(backup_root, 'incoming_data')
    shutil.copytree(incoming, backup_incoming)

    try:
        shutil.rmtree(incoming)
        os.makedirs(incoming)

        with open(os.path.join(incoming, 'sensor_1.csv'), 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['timestamp', 'reading'])
            for timestamp, reading in sensor_1:
                writer.writerow([int(timestamp.timestamp()), reading])

        with open(os.path.join(incoming, 'sensor_2.csv'), 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['timestamp', 'reading'])
            for timestamp, reading in sensor_2:
                writer.writerow([timestamp.strftime('%m/%d/%Y %H:%M:%S'), reading])

        if os.path.exists(db_path):
            os.remove(db_path)
        with sqlite3.connect(db_path) as conn:
            conn.execute('CREATE TABLE hourly_aggregates (sensor_id TEXT, hour_bucket TEXT, avg_reading REAL)')
            conn.execute("INSERT INTO hourly_aggregates VALUES ('stale', '1900-01-01 00:00:00', -1.0)")

        result = subprocess.run(
            ['/usr/bin/python3', script_path],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, \
            f"Pipeline script failed with exit code {result.returncode}. stdout={result.stdout!r}, stderr={result.stderr!r}"

        assert os.path.isfile(db_path), "Pipeline execution did not create metrics.db."
        with sqlite3.connect(db_path) as conn:
            schema = conn.execute("PRAGMA table_info(hourly_aggregates)").fetchall()
            assert schema, "Pipeline execution did not create hourly_aggregates."
            assert [(row[1], row[2].upper()) for row in schema] == [
                ('sensor_id', 'TEXT'),
                ('hour_bucket', 'TEXT'),
                ('avg_reading', 'REAL'),
            ], f"Unexpected hourly_aggregates schema: {schema}"
            rows = conn.execute(
                'SELECT sensor_id, hour_bucket, avg_reading '
                'FROM hourly_aggregates ORDER BY sensor_id, hour_bucket'
            ).fetchall()

        assert len(rows) == len(expected), f"Expected {len(expected)} aggregates, got {rows}"
        for actual, wanted in zip(rows, expected):
            assert actual[0] == wanted[0]
            assert actual[1] == wanted[1]
            assert actual[2] == pytest.approx(wanted[2])

        new_log = open(log_path, 'rb').read()
        assert new_log.startswith(old_log), "Pipeline did not append to the existing log file."
        appended_lines = [
            line for line in new_log[len(old_log):].decode('utf-8', errors='replace').splitlines()
            if line.strip()
        ]
        assert len(appended_lines) == 1, f"Expected one newly appended log line, got: {appended_lines}"
        assert 'Successfully processed 7 total rows.' in appended_lines[0], \
            f"New log line has the wrong raw-row count: {appended_lines[0]!r}"
    finally:
        if os.path.exists(incoming):
            shutil.rmtree(incoming)
        shutil.copytree(backup_incoming, incoming)
        shutil.rmtree(backup_root)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
