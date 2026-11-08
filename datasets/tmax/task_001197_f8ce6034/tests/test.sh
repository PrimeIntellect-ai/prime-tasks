#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess
from datetime import datetime

import pytest

LOG_PATH = '/home/user/system_events.log'
SCRIPT_PATH = '/home/user/process.sh'
OUTPUT_CSV = '/home/user/metrics_summary.csv'


def compute_expected_csv(log_path=LOG_PATH):
    if not os.path.exists(log_path):
        pytest.fail(f"Required log file {log_path} is missing.")

    seen_hashes = set()
    aggregated = {}
    pattern = re.compile(r'^\[(.*?)\] SVC:(.*?) DEDUPE:(.*?) METRICS:(.*)$')

    with open(log_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            match = pattern.match(line)
            if not match:
                continue

            ts_str, service, dedupe_hash, metrics_str = match.groups()
            if dedupe_hash in seen_hashes:
                continue
            seen_hashes.add(dedupe_hash)

            dt = datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")
            bucket_minute = (dt.minute // 15) * 15
            bucket_dt = dt.replace(minute=bucket_minute, second=0)
            bucket_str = bucket_dt.strftime("%Y-%m-%dT%H:%M:%SZ")

            for metric in metrics_str.split(','):
                if '=' not in metric:
                    continue
                key, value = metric.split('=', 1)
                numeric_value = float(value) if '.' in value else int(value)
                aggregate_key = (bucket_str, service, key)
                if aggregate_key not in aggregated or numeric_value > aggregated[aggregate_key]:
                    aggregated[aggregate_key] = numeric_value

    expected_rows = [["bucket", "service", "metric", "max_value"]]
    for bucket, service, metric in sorted(aggregated):
        expected_rows.append([
            bucket,
            service,
            metric,
            str(aggregated[(bucket, service, metric)]),
        ])
    return expected_rows


def read_actual_csv():
    actual_data = []
    with open(OUTPUT_CSV, 'r', newline='') as f:
        for row in csv.reader(f):
            if row:
                actual_data.append(row)
    return actual_data


def assert_output_matches(expected_data):
    assert os.path.exists(OUTPUT_CSV), f"Output file {OUTPUT_CSV} does not exist."
    assert os.path.isfile(OUTPUT_CSV), f"{OUTPUT_CSV} is not a file."

    actual_data = read_actual_csv()
    assert len(actual_data) > 0, f"{OUTPUT_CSV} is empty."
    assert actual_data[0] == expected_data[0], (
        f"Header mismatch. Expected {expected_data[0]}, got {actual_data[0]}"
    )
    assert len(actual_data) == len(expected_data), (
        f"Row count mismatch. Expected {len(expected_data)} rows (including header), "
        f"got {len(actual_data)}"
    )
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, f"Row {i} mismatch. Expected {expected}, got {actual}"


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."
    with open(SCRIPT_PATH, 'rb') as f:
        first_line = f.readline(256).decode('utf-8', errors='replace').strip()
    assert re.match(r'^#!.*(?:/|\b)(?:ba)?sh(?:\s|$)', first_line), (
        f"{SCRIPT_PATH} must be an executable Bash/shell script."
    )


def test_output_csv_exists():
    assert os.path.exists(OUTPUT_CSV), f"Output file {OUTPUT_CSV} does not exist."
    assert os.path.isfile(OUTPUT_CSV), f"{OUTPUT_CSV} is not a file."


def test_output_csv_content():
    assert_output_matches(compute_expected_csv())


def test_script_processes_runtime_log():
    original_log = open(LOG_PATH, 'rb').read()
    original_output = open(OUTPUT_CSV, 'rb').read()

    nonce = secrets.token_hex(12)
    base = 100 + secrets.randbelow(800)
    runtime_log = (
        f"[2024-02-29 23:59:59] SVC:edge DEDUPE:{nonce}a METRICS:cpu={base},mem={base + 900}\n"
        f"[2024-02-29 23:45:01] SVC:ignored DEDUPE:{nonce}a METRICS:cpu={base + 9999}\n"
        f"[2024-03-01 00:00:00] SVC:alpha DEDUPE:{nonce}b METRICS:cpu={base + 10},latency=7.5\n"
        f"[2024-03-01 00:14:59] SVC:alpha DEDUPE:{nonce}c METRICS:cpu={base + 20},latency=6.5\n"
        f"[2024-03-01 00:15:00] SVC:alpha DEDUPE:{nonce}d METRICS:cpu={base + 5},requests={base + 30}\n"
        f"[2024-03-01 00:29:59] SVC:beta DEDUPE:{nonce}e METRICS:disk={base + 40},cpu={base + 1}\n"
        f"[2024-03-01 01:31:17] SVC:alpha DEDUPE:{nonce}f METRICS:mem={base + 2000}\n"
        f"[2024-03-01 00:16:00] SVC:beta DEDUPE:{nonce}d METRICS:cpu={base + 9999}\n"
    ).encode()

    try:
        with open(LOG_PATH, 'wb') as f:
            f.write(runtime_log)
        expected = compute_expected_csv()

        if os.path.exists(OUTPUT_CSV):
            os.remove(OUTPUT_CSV)

        result = subprocess.run(
            [SCRIPT_PATH],
            cwd='/home/user',
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"{SCRIPT_PATH} failed on a runtime-generated log with exit code "
            f"{result.returncode}. stderr: {result.stderr}"
        )
        assert open(LOG_PATH, 'rb').read() == runtime_log, "The processor modified its input log."
        assert_output_matches(expected)
    finally:
        with open(LOG_PATH, 'wb') as f:
            f.write(original_log)
        with open(OUTPUT_CSV, 'wb') as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
