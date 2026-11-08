#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_sensor_task.py
import csv
import io
import json
import os
import random
import secrets
import subprocess
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

HOME = Path('/home/user')
RAW = HOME / 'raw_sensors.csv'
OUTPUT = HOME / 'clean_sensors.jsonl'
LOG = HOME / 'dropped.log'

ORIGINAL_CSV = '''sensor_id,timestamp,temperature
S1,2023-10-01T10:15:00Z,10.0
S1,2023-10-01T10:45:00Z,20.0
S1,2023-10-01T11:30:00Z,30.0
S1,2023-10-01T12:10:00Z,40.0
S1,2023-10-01T12:50:00Z,50.0
S1,2023-10-01T13:20:00Z,120.0
S1,2023-10-01T14:10:00Z,60.0
S2,2023-10-01T08:05:00Z,invalid
S2,2023-10-01T09:15:00Z,-60.0
S2,2023-10-01T10:00:00Z,5.0
S2,2023-10-01T11:00:00Z,10.0
'''

ORIGINAL_EXPECTED = [
    {'sensor_id': 'S1', 'bucket': '2023-10-01T10:00:00Z', 'mean_temp': 15.0, 'rolling_avg': 15.0},
    {'sensor_id': 'S1', 'bucket': '2023-10-01T11:00:00Z', 'mean_temp': 30.0, 'rolling_avg': 22.5},
    {'sensor_id': 'S1', 'bucket': '2023-10-01T12:00:00Z', 'mean_temp': 45.0, 'rolling_avg': 30.0},
    {'sensor_id': 'S1', 'bucket': '2023-10-01T14:00:00Z', 'mean_temp': 60.0, 'rolling_avg': 45.0},
    {'sensor_id': 'S2', 'bucket': '2023-10-01T10:00:00Z', 'mean_temp': 5.0, 'rolling_avg': 5.0},
    {'sensor_id': 'S2', 'bucket': '2023-10-01T11:00:00Z', 'mean_temp': 10.0, 'rolling_avg': 7.5},
]

ORIGINAL_DROPPED = {
    'Dropped sensor S1 at 2023-10-01T13:00:00Z',
    'Dropped sensor S2 at 2023-10-01T09:00:00Z',
}


def read_jsonl():
    assert OUTPUT.exists(), f'The file {OUTPUT} does not exist.'
    assert OUTPUT.is_file(), f'The path {OUTPUT} is not a file.'
    result = []
    with OUTPUT.open() as f:
        for line_number, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                result.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise AssertionError(f'Line {line_number} in {OUTPUT} is not valid JSON: {line}') from exc
    return result


def read_log_lines():
    assert LOG.exists(), f'The file {LOG} does not exist.'
    assert LOG.is_file(), f'The path {LOG} is not a file.'
    with LOG.open() as f:
        return [line.strip() for line in f if line.strip()]


def reset_and_run(script, csv_text):
    RAW.write_text(csv_text)
    for path in (OUTPUT, LOG):
        try:
            path.unlink()
        except FileNotFoundError:
            pass
    completed = subprocess.run(
        ['python3', str(script)],
        cwd=str(HOME),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f'{script} exited with status {completed.returncode}. '
        f'stdout={completed.stdout!r} stderr={completed.stderr!r}'
    )


def check_original():
    lines = set(read_log_lines())
    missing = ORIGINAL_DROPPED - lines
    assert not missing, f'Missing expected lines in {LOG}: {missing}'

    actual = read_jsonl()
    assert len(actual) == len(ORIGINAL_EXPECTED), (
        f'Expected {len(ORIGINAL_EXPECTED)} records in {OUTPUT}, found {len(actual)}.'
    )
    for index, (got, expected) in enumerate(zip(actual, ORIGINAL_EXPECTED)):
        assert got == expected, (
            f'Record at index {index} does not match expected. '
            f'Actual: {got!r}; Expected: {expected!r}'
        )


def derive_expected(csv_text):
    grouped = defaultdict(list)
    reader = csv.DictReader(io.StringIO(csv_text))
    for row in reader:
        try:
            if row.get('temperature') is None or row['temperature'].strip() == '':
                continue
            temperature = float(row['temperature'])
            timestamp = datetime.strptime(row['timestamp'], '%Y-%m-%dT%H:%M:%SZ')
        except (ValueError, TypeError, KeyError):
            continue
        bucket = timestamp.replace(minute=0, second=0, microsecond=0)
        grouped[(row['sensor_id'], bucket)].append(temperature)

    retained = defaultdict(list)
    dropped = []
    for (sensor_id, bucket), values in grouped.items():
        mean = sum(values) / len(values)
        bucket_text = bucket.strftime('%Y-%m-%dT%H:00:00Z')
        if mean > 100.0 or mean < -50.0:
            dropped.append(f'Dropped sensor {sensor_id} at {bucket_text}')
        else:
            retained[sensor_id].append((bucket, mean))

    output = []
    for sensor_id in sorted(retained):
        history = []
        for bucket, mean in sorted(retained[sensor_id]):
            history.append(mean)
            rolling = sum(history[-3:]) / len(history[-3:])
            output.append({
                'sensor_id': sensor_id,
                'bucket': bucket.strftime('%Y-%m-%dT%H:00:00Z'),
                'mean_temp': round(mean, 2),
                'rolling_avg': round(rolling, 2),
            })
    return output, dropped


def make_dynamic_fixture():
    rng = random.SystemRandom()
    token = secrets.token_hex(4)
    sensor_a = f'A_{token}'
    sensor_z = f'Z_{token}'
    year = rng.choice([2024, 2025, 2026])
    month = rng.randint(1, 12)
    day = rng.randint(1, 20)
    base = f'{year:04d}-{month:02d}-{day:02d}'
    p = rng.randint(7, 24)
    q = rng.randint(25, 45)

    rows = [
        [sensor_z, f'{base}T04:05:00Z', str(p)],
        [sensor_z, f'{base}T04:55:00Z', str(p + 2)],
        [sensor_z, f'{base}T05:30:00Z', str(p + 10)],
        [sensor_z, f'{base}T06:10:00Z', '101.0'],
        [sensor_z, f'{base}T07:00:00Z', str(p + 20)],
        [sensor_z, f'{base}T08:59:59Z', '100.0'],
        [sensor_a, f'{base}T02:00:00Z', '-50.0'],
        [sensor_a, f'{base}T03:20:00Z', '-50.01'],
        [sensor_a, f'{base}T04:10:00Z', str(q)],
        [sensor_a, f'{base}T04:50:00Z', str(q + 4)],
        [sensor_a, f'{base}T06:15:00Z', str(q + 8)],
        [sensor_a, f'{base}T05:00:00Z', 'not-a-number'],
        [sensor_a, f'{base}T05:10:00Z', ''],
        [sensor_z, f'{year:04d}-02-30T09:00:00Z', '33.0'],
        [sensor_z, 'definitely-not-a-timestamp', '44.0'],
    ]
    rng.shuffle(rows)
    stream = io.StringIO()
    writer = csv.writer(stream, lineterminator='\n')
    writer.writerow(['sensor_id', 'timestamp', 'temperature'])
    writer.writerows(rows)
    return stream.getvalue()


def check_dynamic(csv_text):
    expected_output, expected_dropped = derive_expected(csv_text)
    actual_output = read_jsonl()
    assert actual_output == expected_output, (
        f'Dynamic output mismatch. Actual: {actual_output!r}; Expected: {expected_output!r}'
    )
    actual_dropped = read_log_lines()
    assert Counter(actual_dropped) == Counter(expected_dropped), (
        f'Dynamic dropped.log mismatch. Actual: {actual_dropped!r}; Expected: {expected_dropped!r}'
    )


def main():
    scripts = sorted(
        path for path in HOME.rglob('*.py')
        if path.is_file() and '__pycache__' not in path.parts
    )
    assert scripts, 'No Python processing script was found under /home/user.'

    dynamic_csv = make_dynamic_fixture()
    failures = []
    winner = None
    for script in scripts:
        try:
            reset_and_run(script, ORIGINAL_CSV)
            check_original()
            reset_and_run(script, dynamic_csv)
            check_dynamic(dynamic_csv)
            winner = script
            break
        except Exception as exc:
            failures.append(f'{script}: {exc}')

    assert winner is not None, 'No submitted Python script passed execution tests:\n' + '\n'.join(failures)

    # Leave the requested outputs generated from the original supplied dataset.
    reset_and_run(winner, ORIGINAL_CSV)
    check_original()


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_sensor_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
