#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import statistics
import subprocess

OUTPUT_PATH = '/home/user/anomalies.csv'
JOURNAL_PATH = '/home/user/sensor.journal'
CALIBRATION_PATH = '/app/calibration_matrix.png'
EXPECTED_HEADER = ['timestamp', 'sensor', 'corrected_value']


def read_calibration_factors():
    text = subprocess.check_output(
        ['tesseract', CALIBRATION_PATH, 'stdout'],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    matches = re.findall(
        r'(SENSOR_(?:ALPHA|BETA|GAMMA))\s*:\s*([0-9]+(?:\.[0-9]+)?)',
        text,
    )
    factors = {sensor: float(value) for sensor, value in matches}
    assert set(factors) == {'SENSOR_ALPHA', 'SENSOR_BETA', 'SENSOR_GAMMA'}, (
        f'Could not recover all calibration factors from {CALIBRATION_PATH}. OCR output: {text!r}'
    )
    return factors


def reject_nonstandard_constant(value):
    raise ValueError(f'Non-standard JSON number: {value}')


def recover_records(factors):
    records = []
    with open(JOURNAL_PATH, 'rb') as journal:
        for raw_line in journal:
            try:
                line = raw_line.decode('utf-8', errors='strict')
                record = json.loads(line, parse_constant=reject_nonstandard_constant)
            except (UnicodeDecodeError, json.JSONDecodeError, ValueError):
                continue

            if not isinstance(record, dict) or set(record) != {'timestamp', 'sensor', 'raw_value'}:
                continue
            timestamp = record['timestamp']
            sensor = record['sensor']
            raw_value = record['raw_value']
            if not isinstance(timestamp, int) or isinstance(timestamp, bool):
                continue
            if not isinstance(sensor, str) or sensor not in factors:
                continue
            if not isinstance(raw_value, (int, float)) or isinstance(raw_value, bool):
                continue
            if not math.isfinite(float(raw_value)):
                continue

            records.append({
                'timestamp': timestamp,
                'sensor': sensor,
                'corrected_value': float(raw_value) * factors[sensor],
            })
    return records


def expected_anomalies():
    factors = read_calibration_factors()
    records = recover_records(factors)
    by_sensor = {sensor: [] for sensor in factors}
    for record in records:
        by_sensor[record['sensor']].append(record['corrected_value'])

    stats = {}
    for sensor, values in by_sensor.items():
        assert values, f'No valid recovered readings for {sensor}'
        stats[sensor] = (statistics.fmean(values), statistics.pstdev(values))

    anomalies = []
    for record in records:
        mean, std_dev = stats[record['sensor']]
        if std_dev > 0 and abs((record['corrected_value'] - mean) / std_dev) > 2.5:
            anomalies.append((
                record['timestamp'],
                record['sensor'],
                f"{record['corrected_value']:.2f}",
            ))
    anomalies.sort(key=lambda row: row[0])
    return anomalies


def read_submission():
    assert os.path.exists(OUTPUT_PATH), (
        f'Output file {OUTPUT_PATH} is missing. The task requires writing anomalies to this path.'
    )
    assert os.path.isfile(OUTPUT_PATH), f'{OUTPUT_PATH} is not a file.'

    with open(OUTPUT_PATH, 'r', encoding='utf-8', newline='') as output:
        rows = list(csv.reader(output))

    assert rows, f'The file {OUTPUT_PATH} is empty. It must contain a header and anomalous records.'
    assert rows[0] == EXPECTED_HEADER, (
        f'Incorrect header in {OUTPUT_PATH}. Expected {EXPECTED_HEADER}, got {rows[0]}'
    )

    parsed = []
    for line_number, row in enumerate(rows[1:], start=2):
        assert len(row) == 3, f'CSV row {line_number} must have exactly 3 columns, got {row!r}'
        timestamp_text, sensor, corrected_text = row
        assert re.fullmatch(r'-?\d+', timestamp_text), (
            f'Invalid integer timestamp on row {line_number}: {timestamp_text!r}'
        )
        assert re.fullmatch(r'-?(?:0|[1-9]\d*)\.\d{2}', corrected_text), (
            f'corrected_value on row {line_number} must be a finite number with exactly 2 decimal places: '
            f'{corrected_text!r}'
        )
        parsed.append((int(timestamp_text), sensor, corrected_text))
    return parsed


def test_anomalies_csv_exists_and_format():
    read_submission()


def test_f1_score_metric_and_record_contents():
    expected = expected_anomalies()
    submitted = read_submission()

    gt_timestamps = {str(row[0]) for row in expected}
    pred_timestamps = {str(row[0]) for row in submitted}
    tp = len(gt_timestamps.intersection(pred_timestamps))
    fp = len(pred_timestamps - gt_timestamps)
    fn = len(gt_timestamps - pred_timestamps)

    if tp == 0:
        f1 = 0.0
    else:
        precision = tp / (tp + fp)
        recall = tp / (tp + fn)
        f1 = 2 * precision * recall / (precision + recall)

    assert f1 >= 0.90, (
        f'Metric threshold failed: F1-Score is {f1:.4f}, which is below the required threshold of 0.90. '
        f'Stats: True Positives={tp}, False Positives={fp}, False Negatives={fn}.'
    )

    assert submitted == sorted(submitted, key=lambda row: row[0]), (
        'The CSV records must be sorted by timestamp in ascending order.'
    )
    assert submitted == expected, (
        'The submitted anomaly records do not exactly match the anomalies obtained by recovering valid '
        'journal records, applying the OCR calibration factors, and using per-sensor population Z-scores.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
