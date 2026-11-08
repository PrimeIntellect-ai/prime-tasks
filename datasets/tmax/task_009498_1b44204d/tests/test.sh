#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import gzip
import json
import os
import secrets
import shutil
import stat
import subprocess
import sys

import pytest

ARCHIVES_DIR = '/home/user/archives'
SCRIPT_PATH = '/home/user/audit.py'
CSV_PATH = '/home/user/fatal_summary.csv'
EXPECTED_EVENTS = []


def remove_path(path):
    if not os.path.lexists(path):
        return
    if os.path.islink(path) or not os.path.isdir(path):
        os.unlink(path)
    else:
        shutil.rmtree(path)


def get_expected_fatal_events():
    assert os.path.isdir(ARCHIVES_DIR), f"Expected fixture directory {ARCHIVES_DIR} is missing."
    fatal_events = []

    for root, _, files in os.walk(ARCHIVES_DIR):
        for filename in files:
            if filename.endswith('.json.gz'):
                file_path = os.path.join(root, filename)
                with gzip.open(file_path, 'rt') as f:
                    for line in f:
                        if not line.strip():
                            continue
                        record = json.loads(line)
                        if record.get('level') == 'FATAL':
                            stack_trace = record.get('stack_trace', '')
                            if not stack_trace:
                                trace_lines = 0
                            else:
                                trace_lines = len(stack_trace.split('\n'))
                            fatal_events.append({
                                'timestamp': record.get('timestamp', ''),
                                'service': record.get('service', ''),
                                'trace_lines': trace_lines,
                            })

    fatal_events.sort(key=lambda event: event['timestamp'])
    return fatal_events


@pytest.fixture(scope='session', autouse=True)
def prepare_archives_and_execute_script():
    assert os.path.lexists(SCRIPT_PATH), f"Expected Python script {SCRIPT_PATH} does not exist."
    script_stat = os.lstat(SCRIPT_PATH)
    assert stat.S_ISREG(script_stat.st_mode), f"Expected {SCRIPT_PATH} to be a regular file."
    assert script_stat.st_size > 0, f"Expected {SCRIPT_PATH} to be non-empty."

    remove_path(ARCHIVES_DIR)
    os.makedirs(os.path.join(ARCHIVES_DIR, '2023', '10', '01'), exist_ok=True)
    os.makedirs(os.path.join(ARCHIVES_DIR, '2023', '10', '02', 'nested'), exist_ok=True)

    token = secrets.token_hex(8)
    auth_logs = [
        {'timestamp': '2023-10-01T08:00:00Z', 'service': f'auth-{token}', 'level': 'INFO', 'stack_trace': ''},
        {'timestamp': '2023-10-01T08:05:00Z', 'service': f'auth-{token}', 'level': 'FATAL', 'stack_trace': 'ConnectionError: DB unreachable\n  at db_conn.py:42\n  at main.py:10'},
        {'timestamp': '2023-10-01T08:10:00Z', 'service': f'auth-{token}', 'level': 'ERROR', 'stack_trace': 'Retry failed'},
    ]
    payment_logs = [
        {'timestamp': '2023-10-02T09:15:00Z', 'service': f'payment-{token}', 'level': 'FATAL', 'stack_trace': 'NullPointerException\n  at payment_processor.py:112'},
        {'timestamp': '2023-10-02T09:20:00Z', 'service': f'payment-{token}', 'level': 'INFO', 'stack_trace': ''},
        {'timestamp': '2023-10-01T07:50:00Z', 'service': f'payment-{token}', 'level': 'FATAL', 'stack_trace': 'OutOfMemoryError\n  at memory_alloc.c:120\n  at wrapper.py:12\n  at init.py:1\n  at main.py:5'},
    ]

    with gzip.open(os.path.join(ARCHIVES_DIR, '2023', '10', '01', 'auth.json.gz'), 'wt') as f:
        for record in auth_logs:
            f.write(json.dumps(record) + '\n')

    with gzip.open(os.path.join(ARCHIVES_DIR, '2023', '10', '02', 'nested', 'payment.json.gz'), 'wt') as f:
        for record in payment_logs:
            f.write(json.dumps(record) + '\n')

    EXPECTED_EVENTS[:] = get_expected_fatal_events()
    assert EXPECTED_EVENTS, 'Verifier fixture unexpectedly contains no FATAL events.'

    remove_path(CSV_PATH)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Expected Python script {SCRIPT_PATH} does not exist."


def test_csv_exists():
    assert os.path.isfile(CSV_PATH), f"Expected output file {CSV_PATH} does not exist."
    assert stat.S_ISREG(os.lstat(CSV_PATH).st_mode), f"Expected {CSV_PATH} to be a regular file."


def test_csv_contents():
    assert os.path.isfile(CSV_PATH), f"Cannot check contents, {CSV_PATH} is missing."

    with open(CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail('CSV file is empty, missing headers.')

        assert headers == ['timestamp', 'service', 'trace_lines'], \
            f"CSV headers are incorrect. Expected ['timestamp', 'service', 'trace_lines'], got {headers}"

        rows = list(reader)

        assert len(rows) == len(EXPECTED_EVENTS), \
            f"Expected {len(EXPECTED_EVENTS)} data rows in CSV, but found {len(rows)}."

        for i, (row, expected) in enumerate(zip(rows, EXPECTED_EVENTS)):
            assert len(row) == 3, f"Row {i+1} does not have exactly 3 columns: {row}"
            assert row[0] == expected['timestamp'], \
                f"Row {i+1} timestamp mismatch. Expected {expected['timestamp']}, got {row[0]}"
            assert row[1] == expected['service'], \
                f"Row {i+1} service mismatch. Expected {expected['service']}, got {row[1]}"
            assert str(row[2]) == str(expected['trace_lines']), \
                f"Row {i+1} trace_lines mismatch. Expected {expected['trace_lines']}, got {row[2]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
