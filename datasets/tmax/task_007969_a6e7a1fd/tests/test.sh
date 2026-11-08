#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import shutil
import subprocess
import tempfile
import pytest

OUTPUT_DIR = '/home/user/output'
OUTPUT_FILE = '/home/user/output/processed_sensors.jsonl'
INPUT_FILE = '/home/user/data/sensor_readings.csv'


def read_jsonl(path):
    actual = []
    with open(path, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                actual.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {path} is not valid JSON: {line}")
    return actual


def test_output_directory_exists():
    """Verify that the output directory was created."""
    assert os.path.isdir(OUTPUT_DIR), f"The output directory {OUTPUT_DIR} does not exist."


def test_output_file_exists():
    """Verify that the output JSON Lines file exists."""
    assert os.path.isfile(OUTPUT_FILE), f"The output file {OUTPUT_FILE} does not exist."


def test_output_file_content():
    """Verify that the output file contains the correct JSON objects in the correct order."""
    expected = [
        {"timestamp": "2023-10-01T09:59:00Z", "sensor_id": "S5", "temp_rolling_avg": 10.0, "notes": "Early reading"},
        {"timestamp": "2023-10-01T10:00:00Z", "sensor_id": "S1", "temp_rolling_avg": 15.0, "notes": "All good"},
        {"timestamp": "2023-10-01T10:03:00Z", "sensor_id": "S3", "temp_rolling_avg": 18.67, "notes": "Normal"},
        {"timestamp": "2023-10-01T10:05:00Z", "sensor_id": "S1", "temp_rolling_avg": 22.33, "notes": "Okay"},
        {"timestamp": "2023-10-01T10:06:00Z", "sensor_id": "S3", "temp_rolling_avg": 21.67, "notes": "Cooling"}
    ]

    actual = read_jsonl(OUTPUT_FILE)
    assert len(actual) == len(expected), f"Expected {len(expected)} records, but found {len(actual)} in {OUTPUT_FILE}."

    for i, (act, exp) in enumerate(zip(actual, expected)):
        assert act == exp, f"Record at index {i} does not match expected.\nExpected: {exp}\nActual: {act}"


def find_python_scripts():
    scripts = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in {'.cache', '.local', '__pycache__'}]
        for name in files:
            path = os.path.join(root, name)
            if not os.path.isfile(path):
                continue
            is_python = name.endswith('.py')
            if not is_python:
                try:
                    with open(path, 'rb') as f:
                        first_line = f.readline(256).lower()
                    is_python = first_line.startswith(b'#!') and b'python' in first_line
                except OSError:
                    continue
            if is_python:
                scripts.append(path)
    return sorted(scripts)


def expected_for(rows):
    valid = []
    for row in sorted(rows, key=lambda item: item['timestamp']):
        if row['status'] != 'OK' or '\n' in row['notes']:
            continue
        try:
            temperature = float(row['temperature'])
        except (TypeError, ValueError):
            continue
        if not -50.0 <= temperature <= 150.0:
            continue
        valid.append((row, temperature))

    expected = []
    temperatures = []
    for row, temperature in valid:
        temperatures.append(temperature)
        avg = round(sum(temperatures[-3:]) / len(temperatures[-3:]), 2)
        expected.append({
            'timestamp': row['timestamp'],
            'sensor_id': row['sensor_id'],
            'temp_rolling_avg': avg,
            'notes': row['notes'],
        })
    return expected


def test_submitted_python_pipeline_executes_on_fresh_input():
    scripts = find_python_scripts()
    assert scripts, "No Python script was found under /home/user."

    token = secrets.token_hex(5)
    day = random.SystemRandom().randint(10, 20)
    temps = random.SystemRandom().sample(range(-20, 90), 4)

    def ts(minute):
        return f'2024-11-{day:02d}T08:{minute:02d}:00Z'

    rows = [
        {'timestamp': ts(0), 'sensor_id': f'A-{token}', 'temperature': str(temps[0]), 'status': 'OK', 'notes': f'first {token}'},
        {'timestamp': ts(1), 'sensor_id': f'B-{token}', 'temperature': '31.5', 'status': 'OK', 'notes': f'embedded\nnewline {token}'},
        {'timestamp': ts(2), 'sensor_id': f'C-{token}', 'temperature': '44', 'status': 'ERROR', 'notes': 'wrong status'},
        {'timestamp': ts(3), 'sensor_id': f'D-{token}', 'temperature': str(temps[1]), 'status': 'OK', 'notes': f'normal {token}'},
        {'timestamp': ts(4), 'sensor_id': f'E-{token}', 'temperature': 'not-a-float', 'status': 'OK', 'notes': 'invalid number'},
        {'timestamp': ts(5), 'sensor_id': f'F-{token}', 'temperature': str(temps[2]), 'status': 'OK', 'notes': f'quoted, value "{token}"'},
        {'timestamp': ts(6), 'sensor_id': f'G-{token}', 'temperature': '-50.0', 'status': 'OK', 'notes': 'lower boundary'},
        {'timestamp': ts(7), 'sensor_id': f'H-{token}', 'temperature': '150.0', 'status': 'OK', 'notes': 'upper boundary'},
        {'timestamp': ts(8), 'sensor_id': f'I-{token}', 'temperature': '12', 'status': 'ok', 'notes': 'case mismatch'},
        {'timestamp': ts(9), 'sensor_id': f'J-{token}', 'temperature': '150.01', 'status': 'OK', 'notes': 'out of range'},
        {'timestamp': ts(10), 'sensor_id': f'K-{token}', 'temperature': str(temps[3]), 'status': 'OK', 'notes': f'last {token}'},
    ]
    random.SystemRandom().shuffle(rows)
    expected = expected_for(rows)

    with open(INPUT_FILE, 'rb') as f:
        original_input = f.read()
    original_output = None
    if os.path.isfile(OUTPUT_FILE):
        with open(OUTPUT_FILE, 'rb') as f:
            original_output = f.read()

    failures = []
    try:
        for script in scripts:
            os.makedirs(os.path.dirname(INPUT_FILE), exist_ok=True)
            with open(INPUT_FILE, 'w', encoding='utf-8', newline='') as f:
                writer = csv.DictWriter(f, fieldnames=['timestamp', 'sensor_id', 'temperature', 'status', 'notes'], lineterminator='\n')
                writer.writeheader()
                writer.writerows(rows)

            if os.path.exists(OUTPUT_FILE):
                os.remove(OUTPUT_FILE)

            try:
                result = subprocess.run(
                    ['python3', script],
                    cwd='/home/user',
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=15,
                )
            except Exception as exc:
                failures.append(f'{script}: could not execute ({exc})')
                continue

            if result.returncode != 0:
                failures.append(f'{script}: exited with {result.returncode}: {result.stderr[-500:]}')
                continue
            if not os.path.isfile(OUTPUT_FILE):
                failures.append(f'{script}: did not create {OUTPUT_FILE}')
                continue

            try:
                actual = read_jsonl(OUTPUT_FILE)
            except Exception as exc:
                failures.append(f'{script}: invalid output ({exc})')
                continue

            if actual == expected:
                return
            failures.append(f'{script}: output did not match the dynamically generated input')

        pytest.fail('No submitted Python script produced the required result when executed. ' + ' | '.join(failures))
    finally:
        with open(INPUT_FILE, 'wb') as f:
            f.write(original_input)
        if original_output is None:
            if os.path.exists(OUTPUT_FILE):
                os.remove(OUTPUT_FILE)
        else:
            os.makedirs(OUTPUT_DIR, exist_ok=True)
            with open(OUTPUT_FILE, 'wb') as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
