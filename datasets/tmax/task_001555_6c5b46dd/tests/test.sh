#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import secrets
import shutil
import subprocess
import sys


def test_cleaned_summary_exists():
    assert os.path.isfile('/home/user/cleaned_summary.csv'), "Output file /home/user/cleaned_summary.csv does not exist."


def test_cleaned_summary_content():
    expected_header = ["user_id", "event_count", "avg_latency", "high_latency_count"]
    expected_rows = [
        ["1", "2", "1000.0", "1"],
        ["2", "1", "1200.0", "1"],
        ["3", "1", "200.0", "0"],
        ["4", "1", "1050.0", "1"]
    ]

    with open('/home/user/cleaned_summary.csv', 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "The file /home/user/cleaned_summary.csv is empty."

    header = rows[0]
    assert header == expected_header, f"Expected header {expected_header}, but got {header}."

    data_rows = rows[1:]
    assert len(data_rows) == len(expected_rows), f"Expected {len(expected_rows)} data rows, but got {len(data_rows)}."

    for i, (expected, actual) in enumerate(zip(expected_rows, data_rows)):
        assert actual[0] == expected[0], f"Row {i+1}: Expected user_id {expected[0]}, got {actual[0]}"
        assert actual[1] == expected[1], f"Row {i+1}: Expected event_count {expected[1]}, got {actual[1]}"
        assert float(actual[2]) == float(expected[2]), f"Row {i+1}: Expected avg_latency {expected[2]}, got {actual[2]}"
        assert actual[3] == expected[3], f"Row {i+1}: Expected high_latency_count {expected[3]}, got {actual[3]}"


def test_script_exists():
    assert os.path.isfile('/home/user/clean_data.py'), "The script /home/user/clean_data.py was not found."


def test_script_executes_pipeline_on_fresh_data():
    data_dir = '/home/user/telemetry_data'
    output_path = '/home/user/cleaned_summary.csv'
    shutil.rmtree(data_dir)
    os.makedirs(data_dir)

    rng = secrets.SystemRandom()
    users = rng.sample(range(20, 900), 4)
    low_a = rng.randrange(100, 750)
    low_b = rng.randrange(1, 900)
    high_a = rng.randrange(1001, 2400)
    high_b = rng.randrange(1001, 2400)
    high_c = rng.randrange(1001, 2400)

    records = [
        [users[0], '2025-01-01T00:00:00Z', 'click', low_a, ''],
        [users[0], '2025-01-01T00:01:00Z', 'scroll', 1000, 80],
        [users[0], '2025-01-01T00:02:00Z', 'view', high_a, 120],
        [users[0], '2025-01-01T00:03:00Z', 'bad', -rng.randrange(1, 500), 999],
        [users[1], '2025-01-01T00:04:00Z', 'view', high_b, ''],
        [users[1], '2025-01-01T00:05:00Z', '', low_a, 300],
        [users[1], '2025-01-01T00:06:00Z', 'click', low_b, 200],
        [users[2], '2025-01-01T00:07:00Z', 'start', 0, 20],
        [users[2], '2025-01-01T00:08:00Z', 'finish', high_c, ''],
        [users[3], '2025-01-01T00:09:00Z', '', 500, 40],
        [users[3], '2025-01-01T00:10:00Z', 'error', -1, 50],
    ]

    header = ['user_id', 'timestamp', 'event_type', 'latency_ms', 'payload_size']
    partitions = [records[4:8], records[0:4], records[8:]]
    for index, partition in enumerate(partitions):
        with open(os.path.join(data_dir, f'random_part_{index}.csv'), 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(header)
            writer.writerows(partition)

    expected = {}
    for user_id, _timestamp, event_type, latency, _payload in records:
        if latency < 0 or event_type is None or event_type == '':
            continue
        bucket = expected.setdefault(user_id, {'latencies': [], 'high': 0})
        bucket['latencies'].append(latency)
        bucket['high'] += int(latency > 1000)

    if os.path.exists(output_path):
        os.remove(output_path)

    result = subprocess.run(
        [sys.executable, '/home/user/clean_data.py'],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"clean_data.py failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert os.path.isfile(output_path), "Running clean_data.py did not create cleaned_summary.csv"

    with open(output_path, newline='') as f:
        rows = list(csv.reader(f))

    expected_header = ['user_id', 'event_count', 'avg_latency', 'high_latency_count']
    assert rows, "The regenerated cleaned_summary.csv is empty"
    assert rows[0] == expected_header, f"Expected header {expected_header}, got {rows[0]}"
    assert all(len(row) == 4 for row in rows[1:]), "Output contains an incorrect number of columns"

    expected_users = sorted(expected)
    assert len(rows[1:]) == len(expected_users), "Output has missing or extra user groups"
    actual_users = [int(row[0]) for row in rows[1:]]
    assert actual_users == expected_users, "Output user groups are not complete and numerically sorted"

    for row, user_id in zip(rows[1:], expected_users):
        values = expected[user_id]
        expected_count = len(values['latencies'])
        expected_average = sum(values['latencies']) / expected_count
        assert int(row[1]) == expected_count, f"Incorrect event_count for user {user_id}"
        assert math.isclose(float(row[2]), expected_average, rel_tol=1e-12, abs_tol=1e-12), f"Incorrect avg_latency for user {user_id}"
        assert int(row[3]) == values['high'], f"Incorrect high_latency_count for user {user_id}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
