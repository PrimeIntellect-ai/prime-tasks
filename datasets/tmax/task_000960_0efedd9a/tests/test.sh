#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import sqlite3
import subprocess
import pytest

RAW_PATH = '/app/raw_logs.jsonl'
CSV_PATH = '/home/user/cleaned.csv'
PRED_PATH = '/home/user/anomaly_ids.txt'
DB_PATH = '/home/user/telemetry.db'
SOURCE_PATH = '/app/json_cleaner.c'
BINARY_PATH = '/tmp/json_cleaner_under_test'
ANOMALY_RE = re.compile(r'ERR-[0-9]{4}-[A-Z]{3}')


def unescape_unicode(value):
    return re.sub(
        r'\\u([0-9a-fA-F]{4})',
        lambda match: chr(int(match.group(1), 16)),
        value,
    )


def expected_rows():
    rows = []
    last_sensor = None
    with open(RAW_PATH, 'r', encoding='utf-8') as raw:
        for line in raw:
            item = json.loads(line)
            sensor = item.get('sensor_val')
            if sensor is None:
                sensor = last_sensor
            else:
                last_sensor = sensor
            rows.append({
                'id': int(item['id']),
                'timestamp': item['timestamp'],
                'message': unescape_unicode(item['message']),
                'sensor_val': float(sensor),
            })
    return rows


EXPECTED = expected_rows()
EXPECTED_IDS = {
    str(row['id']) for row in EXPECTED if ANOMALY_RE.search(row['message'])
}


@pytest.fixture(scope='session', autouse=True)
def compile_and_run_cleaner():
    assert os.path.isfile(SOURCE_PATH), f'C source file is missing at {SOURCE_PATH}.'
    subprocess.run(
        ['gcc', '-O2', '-std=c11', '-Wall', '-Wextra', SOURCE_PATH, '-o', BINARY_PATH],
        check=True,
        timeout=30,
    )
    if os.path.exists(CSV_PATH):
        os.unlink(CSV_PATH)
    subprocess.run([BINARY_PATH], check=True, timeout=30)
    assert os.path.isfile(CSV_PATH), 'Running the compiled cleaner did not create cleaned.csv.'


def calculate_f1(pred_ids, truth_ids):
    if not pred_ids and not truth_ids:
        return 1.0
    if not pred_ids or not truth_ids:
        return 0.0
    tp = len(pred_ids.intersection(truth_ids))
    fp = len(pred_ids - truth_ids)
    fn = len(truth_ids - pred_ids)
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    return 0.0 if precision + recall == 0 else 2 * precision * recall / (precision + recall)


def test_anomaly_f1_score():
    assert os.path.exists(PRED_PATH), f'Expected anomaly IDs file at {PRED_PATH} does not exist.'
    with open(PRED_PATH, 'r', encoding='utf-8') as pred:
        pred_ids = {line.strip() for line in pred if line.strip()}
    f1_score = calculate_f1(pred_ids, EXPECTED_IDS)
    assert f1_score >= 0.95, f'F1 Score {f1_score:.4f} is below the threshold of 0.95.'


def test_cleaned_csv_exists_and_format():
    assert os.path.exists(CSV_PATH), f'Cleaned CSV file at {CSV_PATH} does not exist.'
    with open(CSV_PATH, 'r', encoding='utf-8', newline='') as output:
        raw_lines = output.readlines()
    assert len(raw_lines) == 1001, f'Expected 1001 lines in CSV (1 header + 1000 data rows), found {len(raw_lines)}.'
    assert raw_lines[0].strip() == 'id,timestamp,message,sensor_val', f'CSV header is incorrect. Found: {raw_lines[0].strip()}'
    for i, line in enumerate(raw_lines[1:], start=2):
        parts = line.strip().split(',')
        assert len(parts) >= 4, f'Line {i} in CSV does not have enough columns: {line.strip()}'
        assert parts[-1] != '' and parts[-1].lower() not in ('null', 'none'), f'Missing sensor_val at line {i}: {line.strip()}'

    with open(CSV_PATH, 'r', encoding='utf-8', newline='') as output:
        reader = csv.DictReader(output)
        assert reader.fieldnames == ['id', 'timestamp', 'message', 'sensor_val']
        actual = list(reader)
    assert len(actual) == len(EXPECTED)
    for line_number, (got, want) in enumerate(zip(actual, EXPECTED), start=2):
        assert int(got['id']) == want['id'], f'Incorrect id at CSV line {line_number}.'
        assert got['timestamp'] == want['timestamp'], f'Incorrect timestamp at CSV line {line_number}.'
        assert got['message'] == want['message'], f'Incorrect or non-unescaped message at CSV line {line_number}.'
        try:
            sensor = float(got['sensor_val'])
        except (TypeError, ValueError):
            pytest.fail(f'Invalid sensor_val at CSV line {line_number}: {got["sensor_val"]!r}')
        assert math.isclose(sensor, want['sensor_val'], rel_tol=1e-6, abs_tol=1e-6), f'Incorrect forward-filled sensor_val at CSV line {line_number}.'


def test_telemetry_db_exists_and_populated():
    assert os.path.exists(DB_PATH), f'Database file at {DB_PATH} does not exist.'
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='logs'")
        assert cursor.fetchone() is not None, "Table 'logs' does not exist in the database."
        cursor.execute('SELECT COUNT(*) FROM logs')
        count = cursor.fetchone()[0]
        assert count == 1000, f"Expected 1000 rows in 'logs' table, found {count}."
        cursor.execute('SELECT id, timestamp, message, sensor_val FROM logs ORDER BY CAST(id AS INTEGER)')
        actual = cursor.fetchall()
        assert len(actual) == len(EXPECTED)
        for index, (got, want) in enumerate(zip(actual, EXPECTED), start=1):
            assert int(got[0]) == want['id'], f'Incorrect database id at row {index}.'
            assert got[1] == want['timestamp'], f'Incorrect database timestamp at row {index}.'
            assert got[2] == want['message'], f'Incorrect database message at row {index}.'
            assert math.isclose(float(got[3]), want['sensor_val'], rel_tol=1e-6, abs_tol=1e-6), f'Incorrect database sensor_val at row {index}.'
    finally:
        conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
