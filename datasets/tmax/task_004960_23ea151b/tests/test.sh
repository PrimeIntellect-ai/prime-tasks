#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
from collections import defaultdict
from pathlib import Path

SCRIPT_PATH = '/home/user/process_logs.py'
RAW_LOGS_PATH = '/home/user/raw_logs.txt'
STATS_PATH = '/home/user/device_stats.csv'
SAMPLED_PATH = '/home/user/sampled_logs.txt'


def parse_logs(file_path):
    valid_logs = []
    pattern = re.compile(
        r'^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] (DEVICE_[A-Za-z0-9]+) - STATUS:(\d{3}) - TIME:(\d+)ms - MSG:(.*)$'
    )

    with open(file_path, 'r') as f:
        for original_index, line in enumerate(f):
            line = line.strip('\n')
            match = pattern.match(line)
            if match:
                timestamp, device_id, status_code, response_time, msg = match.groups()
                response_time = int(response_time)
                if response_time >= 0:
                    valid_logs.append({
                        'original_index': original_index,
                        'line': line,
                        'device_id': device_id,
                        'response_time': response_time
                    })
    return valid_logs


def remove_outputs():
    for path in (STATS_PATH, SAMPLED_PATH):
        if os.path.lexists(path):
            os.remove(path)


def run_submission():
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f'{SCRIPT_PATH} did not run cleanly. stdout={result.stdout!r}, '
        f'stderr={result.stderr!r}'
    )


def assert_current_outputs():
    assert os.path.exists(STATS_PATH), f'Expected file {STATS_PATH} does not exist.'
    assert os.path.exists(SAMPLED_PATH), f'Expected file {SAMPLED_PATH} does not exist.'

    valid_logs = parse_logs(RAW_LOGS_PATH)

    # Compute expected stats
    device_times = defaultdict(list)
    for log in valid_logs:
        device_times[log['device_id']].append(log['response_time'])

    expected_stats = []
    for device_id in sorted(device_times.keys()):
        times = device_times[device_id]
        mean_time = sum(times) / len(times)
        expected_stats.append((device_id, str(len(times)), f'{mean_time:.2f}'))

    # Read actual stats
    actual_stats = []
    with open(STATS_PATH, 'r') as f:
        reader = csv.reader(f)
        headers = next(reader, None)
        assert headers == ['device_id', 'log_count', 'mean_response_time_ms'], f'Incorrect CSV headers in {STATS_PATH}.'
        for row in reader:
            actual_stats.append(tuple(row))

    assert actual_stats == expected_stats, f'Content of {STATS_PATH} does not match expected stats.'

    # Compute expected sampled logs
    device_logs = defaultdict(list)
    for log in valid_logs:
        device_logs[log['device_id']].append(log)

    expected_sampled_lines = []
    for device_id in sorted(device_logs.keys()):
        logs = device_logs[device_id]
        # Sort by response_time (asc), then original_index (asc)
        logs.sort(key=lambda x: (x['response_time'], x['original_index']))
        sampled = logs[:2]
        for log in sampled:
            expected_sampled_lines.append(log['line'])

    # Read actual sampled logs
    with open(SAMPLED_PATH, 'r') as f:
        actual_sampled_lines = [line.strip('\n') for line in f]

    assert actual_sampled_lines == expected_sampled_lines, f'Content of {SAMPLED_PATH} does not match expected sampled logs.'


def test_final_state():
    assert os.path.isfile(SCRIPT_PATH), f'Expected Python script {SCRIPT_PATH} does not exist.'
    remove_outputs()
    run_submission()
    assert_current_outputs()


def test_script_processes_unseen_input():
    original_raw = Path(RAW_LOGS_PATH).read_bytes()
    original_stats = Path(STATS_PATH).read_bytes()
    original_sampled = Path(SAMPLED_PATH).read_bytes()

    token = secrets.token_hex(5)
    device_a = f'DEVICE_A{token}'
    device_b = f'DEVICE_B{token}'
    device_c = f'DEVICE_C{token}'
    low = secrets.randbelow(30)
    high = low + 60 + secrets.randbelow(40)
    c_low = 10 + secrets.randbelow(20)

    generated_logs = [
        f'[2025-04-03 10:00:00] {device_a} - STATUS:200 - TIME:{high}ms - MSG:slow reading\n',
        f'[2025-04-03 10:00:01] DEV_BAD-{token} - STATUS:200 - TIME:4ms - MSG:invalid device\n',
        f'[2025-04-03 10:00:02] {device_c} - STATUS:503 - TIME:{c_low + 30}ms - MSG:c slow\n',
        f'[2025-04-03 10:00:03] {device_a} - STATUS:201 - TIME:{low}ms - MSG:first tied reading\n',
        f'[2025-04-03 10:00:04] {device_b} - STATUS:007 - TIME:0ms - MSG:only b reading\n',
        f'[2025-04-03 10:00:05] {device_a} - STATUS:404 - TIME:{low}ms - MSG:second tied reading\n',
        f'[2025-04-03 10:00:06] {device_c} - STATUS:200 - TIME:{c_low}ms - MSG:c fastest\n',
        f'[2025-04-03 10:00:07] {device_c} - STATUS:202 - TIME:{c_low + 10}ms - MSG:c middle\n',
        f'[2025-04-03 10:00:08] {device_b} - STATUS:20 - TIME:1ms - MSG:invalid status\n',
        f'[2025-04-03 10:00:09] {device_b} - STATUS:200 - TIME:-1ms - MSG:negative time\n',
        'unstructured corrupted telemetry\n',
    ]

    try:
        Path(RAW_LOGS_PATH).write_text(''.join(generated_logs))
        remove_outputs()
        run_submission()
        assert_current_outputs()
    finally:
        Path(RAW_LOGS_PATH).write_bytes(original_raw)
        Path(STATS_PATH).write_bytes(original_stats)
        Path(SAMPLED_PATH).write_bytes(original_sampled)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
