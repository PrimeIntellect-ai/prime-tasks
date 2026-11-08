#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import sqlite3
from datetime import datetime, timedelta

import pytest

RAW_PATH = '/app/raw_sensors.csv'
DB_PATH = '/home/user/sensors.db'
REPORT_PATH = '/home/user/rolling_report.txt'
OFFSETS = {'S1': 5.0, 'S2': -3.0}


def load_expected():
    with open(RAW_PATH, 'r', newline='', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['timestamp', 'sensor_id', 'value', 'event_remarks']
        raw = list(reader)

    # Ensure verification is based on the intended immutable fixture.
    assert raw == [
        {'timestamp': '2023-10-01 10:00:00', 'sensor_id': 'S1', 'value': '10.0', 'event_remarks': 'Start\nrecording'},
        {'timestamp': '2023-10-01 11:00:00', 'sensor_id': 'S2', 'value': '25.0', 'event_remarks': 'Normal'},
        {'timestamp': '2023-10-01 12:00:00', 'sensor_id': 'S1', 'value': '13.0', 'event_remarks': 'Spike\ndetected'},
        {'timestamp': '2023-10-01 13:00:00', 'sensor_id': 'S2', 'value': '28.0', 'event_remarks': 'Normal'},
        {'timestamp': '2023-10-01 14:00:00', 'sensor_id': 'S1', 'value': '12.0', 'event_remarks': 'End'},
    ]

    corrected = []
    for row in raw:
        corrected.append({
            'timestamp': row['timestamp'],
            'dt': datetime.strptime(row['timestamp'], '%Y-%m-%d %H:%M:%S'),
            'sensor_id': row['sensor_id'],
            'value': float(row['value']) + OFFSETS[row['sensor_id']],
            'event_remarks': row['event_remarks'],
        })
    corrected.sort(key=lambda r: (r['dt'], r['sensor_id']))

    report_lines = []
    averages = []
    for current in corrected:
        window_start = current['dt'] - timedelta(hours=3)
        values = [
            row['value'] for row in corrected
            if row['sensor_id'] == current['sensor_id']
            and window_start <= row['dt'] <= current['dt']
        ]
        average = sum(values) / len(values)
        averages.append(average)
        report_lines.append(
            f"[{current['timestamp']}] Sensor {current['sensor_id']} Rolling Avg: {average:.2f}"
        )
    return corrected, averages, report_lines


def extract_values(path):
    vals = []
    try:
        with open(path, 'r', encoding='utf-8') as f:
            for line in f:
                match = re.search(r'Rolling Avg:\s*([-\d\.]+)', line)
                if match:
                    vals.append(float(match.group(1)))
    except Exception:
        pass
    return vals


def test_database_contains_every_corrected_csv_record():
    expected_rows, _, _ = load_expected()
    assert os.path.isfile(DB_PATH), f'Database file not found at {DB_PATH}'

    con = sqlite3.connect(DB_PATH)
    try:
        table = con.execute(
            "SELECT type FROM sqlite_master WHERE name = 'measurements'"
        ).fetchone()
        assert table == ('table',), 'measurements must be a SQLite table'

        columns = [row[1] for row in con.execute('PRAGMA table_info(measurements)')]
        for required in ('timestamp', 'sensor_id', 'value', 'event_remarks'):
            assert required in columns, f'Missing measurements column: {required}'

        actual = con.execute(
            'SELECT timestamp, sensor_id, value, event_remarks '
            'FROM measurements ORDER BY timestamp, sensor_id'
        ).fetchall()
    finally:
        con.close()

    assert len(actual) == len(expected_rows), (
        f'Expected {len(expected_rows)} imported records, found {len(actual)}'
    )
    for got, expected in zip(actual, expected_rows):
        assert got[0] == expected['timestamp']
        assert got[1] == expected['sensor_id']
        assert float(got[2]) == pytest.approx(expected['value'], abs=1e-9)
        assert got[3] == expected['event_remarks']


def test_rolling_report_exact_template_order_and_values():
    _, _, expected_lines = load_expected()
    assert os.path.isfile(REPORT_PATH), f'Report file not found at {REPORT_PATH}'
    with open(REPORT_PATH, 'r', encoding='utf-8') as f:
        actual_lines = f.read().splitlines()
    assert actual_lines == expected_lines


def test_rolling_report_mse():
    """Retain the original numerical report assertion with corrected ground truth."""
    assert os.path.isfile(REPORT_PATH), f'Report file not found at {REPORT_PATH}'
    actual = extract_values(REPORT_PATH)
    _, expected, _ = load_expected()

    assert len(actual) == len(expected), (
        f'Expected {len(expected)} rolling average values, but found {len(actual)}. '
        f'Actual values extracted: {actual}'
    )

    mse = sum((a - e) ** 2 for a, e in zip(actual, expected)) / len(expected)
    threshold = 0.1
    assert mse <= threshold, (
        f'MSE of rolling averages is {mse:.4f}, which exceeds {threshold}. '
        f'Expected: {expected}, Actual: {actual}'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
