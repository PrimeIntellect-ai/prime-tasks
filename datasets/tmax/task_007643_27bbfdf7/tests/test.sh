#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import math
import pytest

RAW_CSV = '/home/user/raw_telemetry.csv'
NORMALIZED_CSV = '/home/user/normalized_telemetry.csv'
METRICS_JSON = '/home/user/pipeline_metrics.json'

def compute_expected_stats(raw_csv_path):
    with open(raw_csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        temperatures = []
        humidities = []
        rows = []
        for row in reader:
            rows.append(row)
            temperatures.append(float(row['temperature']))
            humidities.append(float(row['humidity']))

    n = len(temperatures)
    mean_temp = sum(temperatures) / n
    std_temp = math.sqrt(sum((t - mean_temp) ** 2 for t in temperatures) / (n - 1))

    min_hum = min(humidities)
    max_hum = max(humidities)

    expected_normalized = []
    for row in rows:
        norm_row = row.copy()
        norm_row['temperature'] = (float(row['temperature']) - mean_temp) / std_temp
        norm_row['humidity'] = (float(row['humidity']) - min_hum) / (max_hum - min_hum)
        expected_normalized.append(norm_row)

    return {
        'count': n,
        'mean_temp': mean_temp,
        'std_temp': std_temp,
        'min_hum': min_hum,
        'max_hum': max_hum,
        'expected_normalized': expected_normalized
    }

def test_pipeline_metrics_json():
    assert os.path.exists(METRICS_JSON), f"Expected JSON log file not found at {METRICS_JSON}"

    with open(METRICS_JSON, 'r', encoding='utf-8') as f:
        try:
            log = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {METRICS_JSON} is not a valid JSON.")

    assert log.get('pipeline_status') == 'SUCCESS', "pipeline_status should be 'SUCCESS'"

    stats = compute_expected_stats(RAW_CSV)

    assert log.get('records_processed') == stats['count'], f"Expected records_processed to be {stats['count']}"

    temp_stats = log.get('temperature_stats', {})
    assert 'mean' in temp_stats, "Missing 'mean' in temperature_stats"
    assert 'std' in temp_stats, "Missing 'std' in temperature_stats"
    assert math.isclose(temp_stats['mean'], stats['mean_temp'], rel_tol=1e-5), f"Expected temperature mean ~{stats['mean_temp']}"
    assert math.isclose(temp_stats['std'], stats['std_temp'], rel_tol=1e-5), f"Expected temperature std ~{stats['std_temp']}"

    hum_stats = log.get('humidity_stats', {})
    assert 'min' in hum_stats, "Missing 'min' in humidity_stats"
    assert 'max' in hum_stats, "Missing 'max' in humidity_stats"
    assert math.isclose(hum_stats['min'], stats['min_hum'], rel_tol=1e-5), f"Expected humidity min ~{stats['min_hum']}"
    assert math.isclose(hum_stats['max'], stats['max_hum'], rel_tol=1e-5), f"Expected humidity max ~{stats['max_hum']}"

def test_normalized_telemetry_csv():
    assert os.path.exists(NORMALIZED_CSV), f"Expected normalized CSV file not found at {NORMALIZED_CSV}"

    stats = compute_expected_stats(RAW_CSV)
    expected_rows = stats['expected_normalized']

    with open(NORMALIZED_CSV, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in normalized CSV, found {len(actual_rows)}"

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual['timestamp'] == expected['timestamp'], f"Row {i}: timestamp mismatch"
        assert actual['sensor_id'] == expected['sensor_id'], f"Row {i}: sensor_id mismatch"

        try:
            actual_temp = float(actual['temperature'])
            actual_hum = float(actual['humidity'])
        except ValueError:
            pytest.fail(f"Row {i}: temperature or humidity is not a valid float")

        assert math.isclose(actual_temp, expected['temperature'], rel_tol=1e-5, abs_tol=1e-8), \
            f"Row {i}: temperature mismatch. Expected {expected['temperature']}, got {actual_temp}"
        assert math.isclose(actual_hum, expected['humidity'], rel_tol=1e-5, abs_tol=1e-8), \
            f"Row {i}: humidity mismatch. Expected {expected['humidity']}, got {actual_hum}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
