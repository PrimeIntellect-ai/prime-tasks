#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import subprocess


def test_summary_csv_exists_and_content():
    """Test that the summary.csv file exists and has the correct output."""
    file_path = '/home/user/data/summary.csv'
    assert os.path.isfile(file_path), f"File {file_path} does not exist. The task requires creating this output file."

    expected_lines = [
        "sensor_id,mean_temp,max_temp,min_temp",
        "S1,14.27,15.00,10.00",
        "S2,20.83,22.00,0.00"
    ]

    with open(file_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, f"Content of {file_path} does not match expected CSV output."


def test_raw_sensors_file_unmodified():
    """Test that the original raw_sensors.jsonl file was not modified."""
    file_path = '/home/user/data/raw_sensors.jsonl'
    assert os.path.isfile(file_path), f"File {file_path} is missing. The original data must not be deleted."

    expected_content = (
        '{"timestamp": "2023-10-01T00:30:00Z", "sensor_id": "S1", "location": "N\\u00f6rth", "temp": 10.0}\n'
        '{"timestamp": "2023-10-01T02:15:00Z", "sensor_id": "S1", "location": "S\\uXXth", "temp": 12.5}\n'
        '{"timestamp": "2023-10-01T05:45:00Z", "sensor_id": "S1", "location": "East", "temp": 15.0}\n'
        '{"timestamp": "2023-10-01T01:15:00Z", "sensor_id": "S2", "location": "W\\u00e9st", "temp": 20.0}\n'
        '{"timestamp": "2023-10-01T04:10:00Z", "sensor_id": "S2", "location": "W\\uYYst", "temp": 22.0}\n'
    )

    with open(file_path, 'r') as f:
        actual_content = f.read()

    assert actual_content == expected_content, f"Content of {file_path} was modified. The task requires leaving it unchanged."


def test_process_go_exists_and_is_executable_on_derived_input():
    source = '/home/user/workspace/process.go'
    raw_path = '/home/user/data/raw_sensors.jsonl'
    summary_path = '/home/user/data/summary.csv'

    assert os.path.isfile(source), f"File {source} does not exist."
    assert os.path.getsize(source) > 0, f"File {source} is empty."

    with open(raw_path, 'rb') as f:
        original_raw = f.read()
    original_summary = None
    if os.path.exists(summary_path):
        with open(summary_path, 'rb') as f:
            original_summary = f.read()

    token = secrets.token_hex(4)
    sensor_a = f'A_{token}'
    sensor_m = f'M_{token}'
    sensor_z = f'Z_{token}'
    rng = random.SystemRandom()
    base_a = rng.randint(12, 35)
    base_m = rng.randint(8, 30)
    base_z = rng.randint(15, 40)

    records = []

    def add(sensor, hour, minute, temp, malformed=False):
        records.append({
            'timestamp': f'2023-10-01T{hour:02d}:{minute:02d}:00Z',
            'sensor_id': sensor,
            'location': 'MALFORMED' if malformed else 'Nörth',
            'temp': float(temp),
            '_hour': hour,
        })

    add(sensor_a, 0, 45, base_a + 2)
    add(sensor_a, 0, 5, base_a - 2, True)
    add(sensor_a, 2, 50, base_a + 10)
    add(sensor_a, 2, 10, base_a + 6)
    add(sensor_a, 5, 30, base_a - 4, True)

    add(sensor_m, 0, 55, base_m + 4)
    add(sensor_m, 0, 2, base_m, True)
    add(sensor_m, 12, 20, base_m + 12)

    add(sensor_z, 1, 40, base_z + 3, True)
    add(sensor_z, 1, 10, base_z - 1)
    add(sensor_z, 4, 15, base_z + 7)
    add(sensor_z, 23, 5, base_z - 5, True)

    expected_values = {}
    for sensor in (sensor_a, sensor_m, sensor_z):
        hourly = [[] for _ in range(24)]
        for rec in records:
            if rec['sensor_id'] == sensor:
                hourly[rec['_hour']].append(rec['temp'])
        buckets = []
        previous = 0.0
        for values in hourly:
            if values:
                previous = sum(values) / len(values)
            buckets.append(previous)
        expected_values[sensor] = (
            sum(buckets) / 24.0,
            max(buckets),
            min(buckets),
        )

    rng.shuffle(records)
    generated_lines = []
    for rec in records:
        payload = {k: v for k, v in rec.items() if k != '_hour'}
        line = json.dumps(payload, ensure_ascii=True)
        if rec['location'] == 'MALFORMED':
            line = line.replace('MALFORMED', r'S\uXXth')
        generated_lines.append(line)
    generated_raw = ('\n'.join(generated_lines) + '\n').encode()

    try:
        with open(raw_path, 'wb') as f:
            f.write(generated_raw)
        if os.path.exists(summary_path):
            os.remove(summary_path)

        env = os.environ.copy()
        env['GO111MODULE'] = 'off'
        result = subprocess.run(
            ['go', 'run', source],
            cwd='/home/user/workspace',
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=45,
        )
        assert result.returncode == 0, f"process.go failed to compile or run: {result.stderr}"
        assert os.path.isfile(summary_path), "Running process.go did not create summary.csv."

        with open(raw_path, 'rb') as f:
            assert f.read() == generated_raw, "process.go modified its input file."

        with open(summary_path, 'r') as f:
            actual_lines = [line.strip() for line in f if line.strip()]

        expected_lines = ['sensor_id,mean_temp,max_temp,min_temp']
        for sensor in sorted(expected_values):
            mean_temp, max_temp, min_temp = expected_values[sensor]
            expected_lines.append(
                f'{sensor},{mean_temp:.2f},{max_temp:.2f},{min_temp:.2f}'
            )

        assert actual_lines == expected_lines, (
            'process.go did not correctly parse, group, resample, gap-fill, summarize, '
            'sort, and format a newly generated corrupted JSONL input.'
        )
        for line in actual_lines[1:]:
            fields = line.split(',')
            assert len(fields) == 4
            assert all(re.fullmatch(r'-?\d+\.\d{2}', value) for value in fields[1:])
    finally:
        with open(raw_path, 'wb') as f:
            f.write(original_raw)
        if original_summary is None:
            if os.path.exists(summary_path):
                os.remove(summary_path)
        else:
            with open(summary_path, 'wb') as f:
                f.write(original_summary)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
