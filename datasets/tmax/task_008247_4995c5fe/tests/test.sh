#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import secrets
import subprocess
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

HOME = Path('/home/user')
RAW = HOME / 'raw_data'
CSV_PATH = HOME / 'clean_data.csv'
JSON_PATH = HOME / 'anomalies.json'
LOG_PATH = HOME / 'etl.log'


def discover_script():
    candidates = [p for p in HOME.rglob('*.py') if '__pycache__' not in p.parts and RAW not in p.parents]
    preferred = HOME / 'process_etl.py'
    if preferred in candidates:
        script = preferred
    else:
        marked = []
        for path in candidates:
            try:
                source = path.read_text()
            except (OSError, UnicodeDecodeError):
                continue
            if 'clean_data.csv' in source and 'anomalies.json' in source:
                marked.append(path)
        if len(marked) == 1:
            script = marked[0]
        elif len(candidates) == 1:
            script = candidates[0]
        else:
            raise AssertionError('Could not identify the submitted ETL Python script.')

    assert script.is_file(), f'ETL script {script} does not exist.'
    source = script.read_text()
    try:
        tree = ast.parse(source, filename=str(script))
    except SyntaxError as exc:
        raise AssertionError(f'ETL script is not valid Python: {exc}')

    imported_parallel_module = False
    imported_call_names = set()
    parallel_apis = {
        'Pool', 'ThreadPool', 'Process', 'ProcessPoolExecutor',
        'ThreadPoolExecutor', 'submit', 'map', 'starmap', 'map_async',
        'apply_async', 'imap', 'imap_unordered'
    }

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'multiprocessing' or alias.name.startswith('concurrent.futures'):
                    imported_parallel_module = True
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ''
            if module == 'multiprocessing' or module.startswith('multiprocessing.') or module == 'concurrent.futures':
                imported_parallel_module = True
                for alias in node.names:
                    imported_call_names.add(alias.asname or alias.name)

    has_parallel_call = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name):
            if node.func.id in parallel_apis or node.func.id in imported_call_names:
                has_parallel_call = True
        elif isinstance(node.func, ast.Attribute) and node.func.attr in parallel_apis:
            has_parallel_call = True

    assert imported_parallel_module and has_parallel_call, (
        'The ETL script must actually use multiprocessing or concurrent.futures '
        'for parallel extraction.'
    )
    return script


def write_fixture(files):
    RAW.mkdir(parents=True, exist_ok=True)
    for old in RAW.glob('*.jsonl'):
        old.unlink()
    for name, records in files.items():
        with (RAW / name).open('w') as handle:
            for record in records:
                handle.write(json.dumps(record) + '\n')


def clear_outputs():
    for path in (CSV_PATH, JSON_PATH, LOG_PATH):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def run_script(script):
    clear_outputs()
    result = subprocess.run(
        [sys.executable, str(script)],
        cwd=str(HOME),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'ETL script exited with status {result.returncode}.\n'
        f'STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    )


def test_etl_log_validation_gate():
    log_path = '/home/user/etl.log'
    assert os.path.isfile(log_path), f'Log file {log_path} does not exist.'

    with open(log_path, 'r') as f:
        log_content = f.read()

    expected_msg = 'VALIDATION_GATE: Dropped 2 invalid records.'
    assert expected_msg in log_content, (
        f"Could not find the exact validation gate message in {log_path}. "
        f"Expected to find: '{expected_msg}'"
    )


def test_clean_data_csv():
    csv_path = '/home/user/clean_data.csv'
    assert os.path.isfile(csv_path), f'Cleaned data file {csv_path} does not exist.'

    with open(csv_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert reader.fieldnames == ['timestamp', 'sensor_id', 'value'], (
        "CSV headers are incorrect. Expected ['timestamp', 'sensor_id', 'value'], "
        f'got {reader.fieldnames}'
    )

    expected_data = [
        {'timestamp': 1696154400, 'sensor_id': 'A', 'value': 10.0},
        {'timestamp': 1696154401, 'sensor_id': 'A', 'value': 12.0},
        {'timestamp': 1696154402, 'sensor_id': 'A', 'value': 25.0},
        {'timestamp': 1696154404, 'sensor_id': 'B', 'value': 50.0},
        {'timestamp': 1696154405, 'sensor_id': 'B', 'value': 30.0},
    ]

    assert len(rows) == len(expected_data), f'Expected {len(expected_data)} rows in {csv_path}, found {len(rows)}.'

    for i, (actual, expected) in enumerate(zip(rows, expected_data)):
        assert int(actual['timestamp']) == expected['timestamp'], f'Row {i+1}: timestamp mismatch'
        assert actual['sensor_id'] == expected['sensor_id'], f'Row {i+1}: sensor_id mismatch'
        assert math.isclose(float(actual['value']), expected['value'], rel_tol=1e-5), f'Row {i+1}: value mismatch'


def test_anomalies_json():
    json_path = '/home/user/anomalies.json'
    assert os.path.isfile(json_path), f'Anomalies file {json_path} does not exist.'

    with open(json_path, 'r') as f:
        try:
            anomalies = json.load(f)
        except json.JSONDecodeError:
            assert False, f'File {json_path} is not valid JSON.'

    assert isinstance(anomalies, list), f'Expected anomalies to be a JSON array, got {type(anomalies).__name__}.'

    expected_anomalies = [
        {
            'timestamp': 1696154402,
            'sensor_id': 'A',
            'previous_value': 12.0,
            'current_value': 25.0,
            'difference': 13.0,
        },
        {
            'timestamp': 1696154405,
            'sensor_id': 'B',
            'previous_value': 50.0,
            'current_value': 30.0,
            'difference': 20.0,
        },
    ]

    assert len(anomalies) == len(expected_anomalies), f'Expected {len(expected_anomalies)} anomalies, found {len(anomalies)}.'

    for i, (actual, expected) in enumerate(zip(anomalies, expected_anomalies)):
        assert actual.get('timestamp') == expected['timestamp'], f'Anomaly {i+1}: timestamp mismatch'
        assert actual.get('sensor_id') == expected['sensor_id'], f'Anomaly {i+1}: sensor_id mismatch'
        assert math.isclose(float(actual.get('previous_value', 0)), expected['previous_value'], rel_tol=1e-5), f'Anomaly {i+1}: previous_value mismatch'
        assert math.isclose(float(actual.get('current_value', 0)), expected['current_value'], rel_tol=1e-5), f'Anomaly {i+1}: current_value mismatch'
        assert math.isclose(float(actual.get('difference', 0)), expected['difference'], rel_tol=1e-5), f'Anomaly {i+1}: difference mismatch'


def derive_expected(files):
    invalid = 0
    unique = set()
    aligned = defaultdict(list)

    for records in files.values():
        for record in records:
            if 'ts' not in record or 'sensor_id' not in record or 'value' not in record or record['value'] is None:
                invalid += 1
                continue
            key = (record['ts'], record['sensor_id'], float(record['value']))
            if key in unique:
                continue
            unique.add(key)
            parsed = datetime.fromisoformat(record['ts'].replace('Z', '+00:00'))
            timestamp = math.floor(parsed.timestamp())
            aligned[(timestamp, record['sensor_id'])].append(float(record['value']))

    rows = []
    by_sensor = defaultdict(list)
    for (timestamp, sensor_id), values in aligned.items():
        value = sum(values) / len(values)
        row = {'timestamp': timestamp, 'sensor_id': sensor_id, 'value': value}
        rows.append(row)
        by_sensor[sensor_id].append(row)
    rows.sort(key=lambda row: (row['timestamp'], row['sensor_id']))

    anomalies = []
    for sensor_id, sensor_rows in by_sensor.items():
        sensor_rows.sort(key=lambda row: row['timestamp'])
        for previous, current in zip(sensor_rows, sensor_rows[1:]):
            difference = abs(current['value'] - previous['value'])
            if difference > 10.0:
                anomalies.append({
                    'timestamp': current['timestamp'],
                    'sensor_id': sensor_id,
                    'previous_value': previous['value'],
                    'current_value': current['value'],
                    'difference': difference,
                })
    anomalies.sort(key=lambda item: (item['timestamp'], item['sensor_id']))
    return invalid, rows, anomalies


def assert_dynamic_outputs(expected_invalid, expected_rows, expected_anomalies):
    assert LOG_PATH.is_file(), 'Dynamic run did not create etl.log.'
    expected_line = f'VALIDATION_GATE: Dropped {expected_invalid} invalid records.'
    assert expected_line in LOG_PATH.read_text().splitlines(), f'Missing exact log line: {expected_line}'

    assert CSV_PATH.is_file(), 'Dynamic run did not create clean_data.csv.'
    with CSV_PATH.open(newline='') as handle:
        reader = csv.DictReader(handle)
        actual_rows = list(reader)
    assert reader.fieldnames == ['timestamp', 'sensor_id', 'value']
    assert len(actual_rows) == len(expected_rows)
    for index, (actual, expected) in enumerate(zip(actual_rows, expected_rows), 1):
        assert int(actual['timestamp']) == expected['timestamp'], f'Dynamic row {index}: timestamp mismatch'
        assert actual['sensor_id'] == expected['sensor_id'], f'Dynamic row {index}: sensor_id mismatch'
        assert math.isclose(float(actual['value']), expected['value'], rel_tol=1e-9, abs_tol=1e-9), f'Dynamic row {index}: value mismatch'

    assert JSON_PATH.is_file(), 'Dynamic run did not create anomalies.json.'
    with JSON_PATH.open() as handle:
        actual_anomalies = json.load(handle)
    assert isinstance(actual_anomalies, list)
    assert len(actual_anomalies) == len(expected_anomalies)
    for index, (actual, expected) in enumerate(zip(actual_anomalies, expected_anomalies), 1):
        assert actual.get('timestamp') == expected['timestamp'], f'Dynamic anomaly {index}: timestamp mismatch'
        assert actual.get('sensor_id') == expected['sensor_id'], f'Dynamic anomaly {index}: sensor_id mismatch'
        for field in ('previous_value', 'current_value', 'difference'):
            assert field in actual, f'Dynamic anomaly {index}: missing {field}'
            assert math.isclose(float(actual[field]), expected[field], rel_tol=1e-9, abs_tol=1e-9), f'Dynamic anomaly {index}: {field} mismatch'


def test_pipeline_end_to_end():
    script = discover_script()

    original = {
        'data_01.jsonl': [
            {'ts': '2023-10-01T10:00:00.100Z', 'sensor_id': 'A', 'value': 10.0},
            {'ts': '2023-10-01T10:00:00.100Z', 'sensor_id': 'A', 'value': 10.0},
            {'ts': '2023-10-01T10:00:01.900Z', 'sensor_id': 'A', 'value': 12.0},
            {'ts': '2023-10-01T10:00:03.000Z', 'sensor_id': 'A', 'value': None},
            {'sensor_id': 'A', 'value': 5.0},
        ],
        'data_02.jsonl': [
            {'ts': '2023-10-01T10:00:02.050Z', 'sensor_id': 'A', 'value': 25.0},
            {'ts': '2023-10-01T10:00:04.000Z', 'sensor_id': 'B', 'value': 50.0},
            {'ts': '2023-10-01T10:00:05.100Z', 'sensor_id': 'B', 'value': 20.0},
            {'ts': '2023-10-01T10:00:05.800Z', 'sensor_id': 'B', 'value': 40.0},
        ],
    }
    write_fixture(original)
    run_script(script)
    test_etl_log_validation_gate()
    test_clean_data_csv()
    test_anomalies_json()

    token = secrets.token_hex(5)
    sensor_a = f'sensor-{token}-A'
    sensor_b = f'sensor-{token}-B'
    shift = secrets.randbelow(500) + 1
    dynamic = {
        f'part_{secrets.token_hex(3)}.jsonl': [
            {'ts': '2024-01-01T00:00:00.100Z', 'sensor_id': sensor_a, 'value': shift + 10.0},
            {'ts': '2024-01-01T00:00:00.100Z', 'sensor_id': sensor_a, 'value': shift + 10.0},
            {'ts': '2024-01-01T00:00:00.200Z', 'sensor_id': sensor_b, 'value': shift + 50.0},
            {'ts': '2024-01-01T00:00:03Z', 'sensor_id': sensor_a, 'value': None},
        ],
        f'part_{secrets.token_hex(3)}.jsonl': [
            {'ts': '2024-01-01T00:00:00.900Z', 'sensor_id': sensor_a, 'value': shift + 14.0},
            {'ts': '2024-01-01T00:00:01.700Z', 'sensor_id': sensor_a, 'value': shift + 22.0},
            {'ts': '2024-01-01T00:00:01.100Z', 'sensor_id': sensor_b, 'value': shift + 30.0},
            {'sensor_id': sensor_a, 'value': shift + 5.0},
        ],
        f'part_{secrets.token_hex(3)}.jsonl': [
            {'ts': '2024-01-01T01:00:02.750+01:00', 'sensor_id': sensor_a, 'value': shift + 32.5},
            {'ts': '2024-01-01T00:00:01.800Z', 'sensor_id': sensor_b, 'value': shift + 40.0},
            {'ts': '2024-01-01T00:00:00.200Z', 'sensor_id': sensor_b, 'value': shift + 50.0},
            {'ts': '2024-01-01T00:00:04Z', 'value': shift + 1.0},
        ],
    }
    expected_invalid, expected_rows, expected_anomalies = derive_expected(dynamic)
    write_fixture(dynamic)
    run_script(script)
    assert_dynamic_outputs(expected_invalid, expected_rows, expected_anomalies)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
