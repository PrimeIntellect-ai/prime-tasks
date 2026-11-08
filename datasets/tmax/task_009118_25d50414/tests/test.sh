#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import random
import subprocess
from pathlib import Path

import pytest

INPUT_FILE = Path('/home/user/sensor_data.csv')
PROJECT_DIR = Path('/home/user/etl_pipeline')
CLEAN_FILE = Path('/home/user/clean_data.jsonl')
ANOMALIES_FILE = Path('/home/user/anomalies.jsonl')
INVALID_FILE = Path('/home/user/invalid_count.txt')

ORIGINAL_INPUT = INPUT_FILE.read_bytes()


def get_expected_data(input_file='/home/user/sensor_data.csv'):
    invalid_count = 0
    clean_data = []
    anomalies = []

    if not os.path.exists(input_file):
        return 0, [], []

    with open(input_file, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                voltage = float(row['voltage'])
                current = float(row['current'])
                sensor_id = row['sensor_id'].strip()
                timestamp = row['timestamp']

                if not timestamp or not sensor_id or voltage < 0.0 or current < 0.0:
                    invalid_count += 1
                    continue

                power = voltage * current
                record = {
                    "timestamp": timestamp,
                    "sensor_id": sensor_id,
                    "voltage": voltage,
                    "current": current,
                    "power": power
                }

                if power > 5000.0:
                    anomalies.append(record)
                else:
                    clean_data.append(record)

            except (ValueError, KeyError, TypeError):
                invalid_count += 1

    return invalid_count, clean_data, anomalies


def remove_outputs():
    for path in (CLEAN_FILE, ANOMALIES_FILE, INVALID_FILE):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def run_application():
    remove_outputs()
    result = subprocess.run(
        ['cargo', 'run', '--quiet'],
        cwd=str(PROJECT_DIR),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f'Rust application failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def read_jsonl(path):
    records = []
    with open(path, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                assert False, f'Invalid JSON on line {line_num} in {path}'
            assert isinstance(record, dict), f'JSON on line {line_num} in {path} is not an object'
            records.append(record)
    return records


@pytest.fixture(scope='module', autouse=True)
def build_and_run_rust_application():
    assert PROJECT_DIR.is_dir(), f'Missing Rust project directory: {PROJECT_DIR}'
    assert (PROJECT_DIR / 'Cargo.toml').is_file(), 'Missing Cargo.toml in /home/user/etl_pipeline'
    rust_sources = [p for p in PROJECT_DIR.rglob('*.rs') if p.is_file()]
    assert rust_sources, 'No Rust source files found in /home/user/etl_pipeline'

    expected_before_run = get_expected_data()
    run_application()
    assert INPUT_FILE.read_bytes() == ORIGINAL_INPUT, 'The application modified sensor_data.csv'
    assert get_expected_data() == expected_before_run


def test_invalid_count_file():
    expected_invalid_count, _, _ = get_expected_data()
    file_path = '/home/user/invalid_count.txt'

    assert os.path.exists(file_path), f"File missing: {file_path}"

    with open(file_path, 'r') as f:
        content = f.read().strip()

    assert content.isdigit(), f"Content of {file_path} is not a valid integer: '{content}'"
    assert int(content) == expected_invalid_count, f"Expected {expected_invalid_count} invalid rows, found {content}"


def test_clean_data_jsonl():
    _, expected_clean_data, _ = get_expected_data()
    file_path = '/home/user/clean_data.jsonl'

    assert os.path.exists(file_path), f"File missing: {file_path}"

    actual_clean_data = []
    with open(file_path, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                actual_clean_data.append(record)
            except json.JSONDecodeError:
                assert False, f"Invalid JSON on line {line_num} in {file_path}"

    assert len(actual_clean_data) == len(expected_clean_data), \
        f"Expected {len(expected_clean_data)} clean rows, found {len(actual_clean_data)}"

    for i, record in enumerate(actual_clean_data):
        assert "timestamp" in record, "Missing 'timestamp' in clean_data.jsonl"
        assert "sensor_id" in record, "Missing 'sensor_id' in clean_data.jsonl"
        assert "voltage" in record, "Missing 'voltage' in clean_data.jsonl"
        assert "current" in record, "Missing 'current' in clean_data.jsonl"
        assert "power" in record, "Missing 'power' in clean_data.jsonl"

        power = record["power"]
        assert power <= 5000.0, f"Found power > 5000.0 in clean_data.jsonl: {power}"

        expected_power = record["voltage"] * record["current"]
        assert abs(power - expected_power) < 1e-6, f"Incorrect power calculation in clean_data.jsonl: {power} != {expected_power}"

    assert actual_clean_data == expected_clean_data, \
        'clean_data.jsonl records do not exactly match the valid non-anomalous input rows'


def test_anomalies_jsonl():
    _, _, expected_anomalies = get_expected_data()
    file_path = '/home/user/anomalies.jsonl'

    assert os.path.exists(file_path), f"File missing: {file_path}"

    actual_anomalies = []
    with open(file_path, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                actual_anomalies.append(record)
            except json.JSONDecodeError:
                assert False, f"Invalid JSON on line {line_num} in {file_path}"

    assert len(actual_anomalies) == len(expected_anomalies), \
        f"Expected {len(expected_anomalies)} anomalous rows, found {len(actual_anomalies)}"

    for i, record in enumerate(actual_anomalies):
        assert "timestamp" in record, "Missing 'timestamp' in anomalies.jsonl"
        assert "sensor_id" in record, "Missing 'sensor_id' in anomalies.jsonl"
        assert "voltage" in record, "Missing 'voltage' in anomalies.jsonl"
        assert "current" in record, "Missing 'current' in anomalies.jsonl"
        assert "power" in record, "Missing 'power' in anomalies.jsonl"

        power = record["power"]
        assert power > 5000.0, f"Found power <= 5000.0 in anomalies.jsonl: {power}"

        expected_power = record["voltage"] * record["current"]
        assert abs(power - expected_power) < 1e-6, f"Incorrect power calculation in anomalies.jsonl: {power} != {expected_power}"

    assert actual_anomalies == expected_anomalies, \
        'anomalies.jsonl records do not exactly match the anomalous input rows'


def test_total_row_count():
    expected_invalid, expected_clean, expected_anomalies = get_expected_data()

    invalid_path = '/home/user/invalid_count.txt'
    clean_path = '/home/user/clean_data.jsonl'
    anomalies_path = '/home/user/anomalies.jsonl'

    invalid_count = 0
    if os.path.exists(invalid_path):
        with open(invalid_path, 'r') as f:
            content = f.read().strip()
            if content.isdigit():
                invalid_count = int(content)

    clean_count = 0
    if os.path.exists(clean_path):
        with open(clean_path, 'r') as f:
            clean_count = sum(1 for line in f if line.strip())

    anomalies_count = 0
    if os.path.exists(anomalies_path):
        with open(anomalies_path, 'r') as f:
            anomalies_count = sum(1 for line in f if line.strip())

    total_processed = invalid_count + clean_count + anomalies_count

    input_file = '/home/user/sensor_data.csv'
    total_input = 0
    if os.path.exists(input_file):
        with open(input_file, 'r') as f:
            total_input = sum(1 for _ in f) - 1

    assert total_processed == total_input, \
        f"Sum of processed rows ({total_processed}) does not match total input rows ({total_input})."


def test_application_on_generated_input():
    buffer = io.StringIO(newline='')
    writer = csv.writer(buffer)
    writer.writerow(['timestamp', 'sensor_id', 'voltage', 'current'])

    rng = random.Random(917263)
    for i in range(12000):
        timestamp = f'2025-04-{1 + (i % 28):02d}T{(i // 3600) % 24:02d}:{(i // 60) % 60:02d}:{i % 60:02d}Z'
        sensor_id = f'X-{rng.randrange(1, 250)}'
        kind = i % 17
        if kind == 0:
            writer.writerow([timestamp, sensor_id, -rng.uniform(0.1, 20.0), rng.uniform(0.1, 30.0)])
        elif kind == 1:
            writer.writerow([timestamp, sensor_id, rng.uniform(1.0, 250.0), -rng.uniform(0.1, 10.0)])
        elif kind == 2:
            writer.writerow([timestamp, '', 120.0, 12.0])
        elif kind == 3:
            writer.writerow([timestamp, sensor_id, 'not-a-number', 4.0])
        elif kind == 4:
            writer.writerow(['', sensor_id, 120.0, 12.0])
        elif kind == 5:
            writer.writerow([timestamp, sensor_id, 250.0, 20.0])
        elif kind == 6:
            writer.writerow([timestamp, sensor_id, 250.0, 20.0004])
        else:
            voltage = round(rng.uniform(1.0, 220.0), 4)
            current = round(rng.uniform(0.1, 18.0), 4)
            writer.writerow([timestamp, sensor_id, voltage, current])

    generated_input = buffer.getvalue().encode()
    INPUT_FILE.write_bytes(generated_input)
    expected_invalid, expected_clean, expected_anomalies = get_expected_data()

    try:
        run_application()
        assert INPUT_FILE.read_bytes() == generated_input, 'The application modified the generated input CSV'
        assert INVALID_FILE.is_file(), f'File missing: {INVALID_FILE}'
        assert CLEAN_FILE.is_file(), f'File missing: {CLEAN_FILE}'
        assert ANOMALIES_FILE.is_file(), f'File missing: {ANOMALIES_FILE}'

        invalid_text = INVALID_FILE.read_text().strip()
        assert invalid_text.isdigit(), f"Content of {INVALID_FILE} is not a valid integer: '{invalid_text}'"
        assert int(invalid_text) == expected_invalid
        assert read_jsonl(CLEAN_FILE) == expected_clean
        assert read_jsonl(ANOMALIES_FILE) == expected_anomalies
    finally:
        INPUT_FILE.write_bytes(ORIGINAL_INPUT)
        run_application()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
