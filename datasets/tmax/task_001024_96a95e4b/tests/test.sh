#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import stat
import subprocess

import pytest

HOME = '/home/user'
CSV_PATH = HOME + '/processed_features.csv'
LOG_PATH = HOME + '/pipeline_log.json'
SOURCE_PATH = HOME + '/sensor_pipeline.cpp'
RAW_PATH = HOME + '/raw_sensor_data.csv'
CSV_HEADER = ['time_min', 'norm_temp', 'norm_hum', 'roll_mean_temp', 'roll_mean_hum']
LOG_KEYS = {
    'total_rows_input',
    'total_rows_output',
    'temperature_mean',
    'temperature_stddev',
    'humidity_mean',
    'humidity_stddev',
}
FLOAT_KEYS = {
    'temperature_mean',
    'temperature_stddev',
    'humidity_mean',
    'humidity_stddev',
}
FOUR_DECIMALS = re.compile(r'^-?\d+\.\d{4}$')


def read_log_checked(path):
    raw = open(path, 'r').read()
    try:
        pairs = json.loads(raw, object_pairs_hook=lambda p: p)
    except json.JSONDecodeError as exc:
        pytest.fail(f'File {path} is not valid JSON: {exc}')

    assert isinstance(pairs, list), 'The JSON log must be a single object.'
    keys = [key for key, _ in pairs]
    assert len(keys) == len(set(keys)), 'The JSON log contains duplicate keys.'
    assert set(keys) == LOG_KEYS, f'JSON keys {set(keys)} do not match {LOG_KEYS}'
    data = dict(pairs)
    assert type(data['total_rows_input']) is int
    assert type(data['total_rows_output']) is int

    for key in FLOAT_KEYS:
        assert type(data[key]) in (int, float) and not isinstance(data[key], bool)
        match = re.search(r'"' + re.escape(key) + r'"\s*:\s*(-?\d+\.\d{4})(?=\s*[,}])', raw)
        assert match, f'{key} must be written as a JSON number with exactly four decimal places.'
    return data


def assert_csv_format(rows):
    for i, row in enumerate(rows):
        assert len(row) == 5, f'CSV row {i} has {len(row)} columns instead of 5.'
        assert re.fullmatch(r'-?\d+', row[0]), f'Invalid integer time_min in row {i}: {row[0]}'
        for value in row[1:]:
            assert FOUR_DECIMALS.fullmatch(value), f'Float {value!r} in row {i} is not formatted to exactly four decimal places.'


def test_processed_features_csv_exists():
    assert os.path.isfile(CSV_PATH), f'File {CSV_PATH} is missing.'


def test_pipeline_log_json_exists():
    assert os.path.isfile(LOG_PATH), f'File {LOG_PATH} is missing.'


def test_processed_features_csv_content():
    expected_rows = [
        [0, -1.4639, -1.4639, -1.4639, -1.4639],
        [1, -0.8783, -0.8783, -1.1711, -1.1711],
        [2, -0.2928, -0.2928, -0.8783, -0.8783],
        [3, 0.2928, 0.2928, -0.5855, -0.5855],
        [4, 0.8783, 0.8783, -0.2928, -0.2928],
        [5, 1.4639, 1.4639, 0.2928, 0.2928],
    ]
    with open(CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == CSV_HEADER, f'CSV header {header} does not match expected {CSV_HEADER}'
        rows = list(reader)

    assert_csv_format(rows)
    assert len(rows) == len(expected_rows), f'Expected {len(expected_rows)} rows, got {len(rows)}'
    for i, row in enumerate(rows):
        assert int(row[0]) == expected_rows[i][0]
        for j in range(1, 5):
            assert math.isclose(float(row[j]), expected_rows[i][j], abs_tol=0.0002), \
                f'Row {i} column {header[j]} mismatch: {row[j]} != {expected_rows[i][j]}'


def test_pipeline_log_json_content():
    data = read_log_checked(LOG_PATH)
    assert data['total_rows_input'] == 3
    assert data['total_rows_output'] == 6
    assert math.isclose(data['temperature_mean'], 22.5000, abs_tol=0.0002)
    assert math.isclose(data['temperature_stddev'], 1.7078, abs_tol=0.0002)
    assert math.isclose(data['humidity_mean'], 52.5000, abs_tol=0.0002)
    assert math.isclose(data['humidity_stddev'], 1.7078, abs_tol=0.0002)


def test_source_and_compiled_executable_exist():
    assert os.path.isfile(SOURCE_PATH), f'File {SOURCE_PATH} is missing.'
    assert os.path.getsize(SOURCE_PATH) > 0, f'File {SOURCE_PATH} is empty.'

    executables = []
    for name in os.listdir(HOME):
        path = os.path.join(HOME, name)
        if not os.path.isfile(path) or not os.access(path, os.X_OK):
            continue
        try:
            with open(path, 'rb') as f:
                if f.read(4) == b'\x7fELF':
                    executables.append(path)
        except OSError:
            pass
    assert executables, 'No compiled executable was found in /home/user.'


def interpolate_fixture(points):
    by_time = {t: (temp, hum) for t, temp, hum in points}
    result = []
    lo, hi = min(by_time), max(by_time)
    known = sorted(by_time)
    for t in range(lo, hi + 1):
        if t in by_time:
            temp, hum = by_time[t]
        else:
            left = max(k for k in known if k < t)
            right = min(k for k in known if k > t)
            ratio = (t - left) / (right - left)
            temp = by_time[left][0] + ratio * (by_time[right][0] - by_time[left][0])
            hum = by_time[left][1] + ratio * (by_time[right][1] - by_time[left][1])
        result.append((t, temp, hum))
    return result


def test_zz_pipeline_executes_on_unseen_input():
    points = [
        (10, 10.0, 80.0),
        (13, 16.0, 74.0),
        (17, 8.0, 90.0),
        (20, 20.0, 60.0),
    ]
    with open(RAW_PATH, 'w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['time_min', 'temperature', 'humidity'])
        writer.writerows(points)

    verifier_exe = '/tmp/verifier_sensor_pipeline'
    compiled = subprocess.run(
        ['g++', '-std=c++17', '-O2', SOURCE_PATH, '-o', verifier_exe],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compiled.returncode == 0, f'sensor_pipeline.cpp did not compile:\n{compiled.stderr}'

    for path in (CSV_PATH, LOG_PATH):
        if os.path.exists(path):
            os.remove(path)
    run = subprocess.run(
        [verifier_exe], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=30,
    )
    assert run.returncode == 0, f'Compiled pipeline failed:\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}'
    assert os.path.isfile(CSV_PATH), 'Executing the pipeline did not create processed_features.csv.'
    assert os.path.isfile(LOG_PATH), 'Executing the pipeline did not create pipeline_log.json.'

    filled = interpolate_fixture(points)
    temps = [row[1] for row in filled]
    hums = [row[2] for row in filled]
    temp_mean = sum(temps) / len(temps)
    hum_mean = sum(hums) / len(hums)
    temp_std = math.sqrt(sum((x - temp_mean) ** 2 for x in temps) / len(temps))
    hum_std = math.sqrt(sum((x - hum_mean) ** 2 for x in hums) / len(hums))
    norm_t = [(x - temp_mean) / temp_std for x in temps]
    norm_h = [(x - hum_mean) / hum_std for x in hums]
    expected = []
    for i, (t, _, _) in enumerate(filled):
        start = max(0, i - 4)
        expected.append([
            t,
            norm_t[i],
            norm_h[i],
            sum(norm_t[start:i + 1]) / (i - start + 1),
            sum(norm_h[start:i + 1]) / (i - start + 1),
        ])

    with open(CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = list(reader)
    assert header == CSV_HEADER
    assert_csv_format(rows)
    assert len(rows) == len(expected)
    for i, (actual, wanted) in enumerate(zip(rows, expected)):
        assert int(actual[0]) == wanted[0]
        for j in range(1, 5):
            assert math.isclose(float(actual[j]), wanted[j], abs_tol=0.00015), \
                f'Dynamic row {i}, column {CSV_HEADER[j]}: {actual[j]} != {wanted[j]:.8f}'

    data = read_log_checked(LOG_PATH)
    assert data['total_rows_input'] == len(points)
    assert data['total_rows_output'] == len(filled)
    assert math.isclose(data['temperature_mean'], temp_mean, abs_tol=0.00015)
    assert math.isclose(data['temperature_stddev'], temp_std, abs_tol=0.00015)
    assert math.isclose(data['humidity_mean'], hum_mean, abs_tol=0.00015)
    assert math.isclose(data['humidity_stddev'], hum_std, abs_tol=0.00015)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
