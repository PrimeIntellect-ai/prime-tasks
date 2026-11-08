#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import re
import random
import secrets
import subprocess
from datetime import datetime, timedelta, timezone
import pytest

RAW_LOGS_PATH = "/home/user/data/raw_logs.csv"
OUTPUT_JSON_PATH = "/home/user/investigation_sample.json"
PROCESS_PY_PATH = "/home/user/process_logs.py"
PIPELINE_SH_PATH = "/home/user/pipeline.sh"
CRON_TXT_PATH = "/home/user/cron.txt"

def parse_iso(ts_str):
    if ts_str.endswith('Z'):
        ts_str = ts_str[:-1] + '+00:00'
    return datetime.fromisoformat(ts_str)

def format_iso(dt):
    return dt.strftime('%Y-%m-%dT%H:%M:%SZ')

def compute_expected_data():
    if not os.path.exists(RAW_LOGS_PATH):
        return []

    records = []
    with open(RAW_LOGS_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            records.append({
                'timestamp': parse_iso(row['timestamp']),
                'level': row['level'],
                'response_ms': float(row['response_ms'])
            })

    if not records:
        return []

    min_ts = min(r['timestamp'] for r in records)
    max_ts = max(r['timestamp'] for r in records)
    start_bin = min_ts.replace(minute=min_ts.minute - (min_ts.minute % 5), second=0, microsecond=0)
    end_bin = max_ts.replace(minute=max_ts.minute - (max_ts.minute % 5), second=0, microsecond=0)

    bins = {}
    current = start_bin
    while current <= end_bin:
        bins[current] = {'total_requests': 0, 'error_count': 0, 'sum_response_ms': 0.0, 'avg_response_ms': None}
        current += timedelta(minutes=5)

    for r in records:
        ts = r['timestamp']
        b = ts.replace(minute=ts.minute - (ts.minute % 5), second=0, microsecond=0)
        bins[b]['total_requests'] += 1
        if r['level'] == 'ERROR':
            bins[b]['error_count'] += 1
        bins[b]['sum_response_ms'] += r['response_ms']

    for data in bins.values():
        if data['total_requests'] > 0:
            data['avg_response_ms'] = data['sum_response_ms'] / data['total_requests']

    sorted_bins = sorted(bins.keys())
    for i, b in enumerate(sorted_bins):
        if bins[b]['avg_response_ms'] is None:
            if i > 0 and bins[sorted_bins[i - 1]]['total_requests'] > 0:
                bins[b]['avg_response_ms'] = bins[sorted_bins[i - 1]]['avg_response_ms']
            else:
                bins[b]['avg_response_ms'] = 0.0

    group_a = []
    group_b = []
    for b in sorted_bins:
        item = {
            'timestamp': b,
            'total_requests': bins[b]['total_requests'],
            'error_count': bins[b]['error_count'],
            'avg_response_ms': bins[b]['avg_response_ms']
        }
        if item['error_count'] > 0:
            group_a.append(item)
        else:
            group_b.append(item)

    group_a.sort(key=lambda x: (-x['error_count'], x['timestamp']))
    group_b.sort(key=lambda x: (-x['total_requests'], x['timestamp']))
    final_sample = group_a[:3] + group_b[:3]
    final_sample.sort(key=lambda x: x['timestamp'])

    return [{
        'timestamp': format_iso(item['timestamp']),
        'total_requests': item['total_requests'],
        'error_count': item['error_count'],
        'avg_response_ms': item['avg_response_ms']
    } for item in final_sample]

def assert_output_matches_expected():
    assert os.path.exists(OUTPUT_JSON_PATH), f"Missing output file: {OUTPUT_JSON_PATH}"
    with open(OUTPUT_JSON_PATH, 'r', encoding='utf-8') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_JSON_PATH} is not valid JSON.")

    assert isinstance(actual_data, list), "JSON output must be a list of objects (orient='records')."
    assert len(actual_data) == 6, f"Expected exactly 6 records in output, found {len(actual_data)}."

    expected_data = compute_expected_data()
    assert len(expected_data) == 6, "Expected data computation failed to find 6 records."
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual.get('timestamp') == expected['timestamp'], f"Record {i}: Expected timestamp {expected['timestamp']}, got {actual.get('timestamp')}"
        assert actual.get('total_requests') == expected['total_requests'], f"Record {i}: Expected total_requests {expected['total_requests']}, got {actual.get('total_requests')}"
        assert actual.get('error_count') == expected['error_count'], f"Record {i}: Expected error_count {expected['error_count']}, got {actual.get('error_count')}"
        actual_avg = actual.get('avg_response_ms')
        expected_avg = expected['avg_response_ms']
        assert actual_avg is not None, f"Record {i}: Missing avg_response_ms"
        assert abs(actual_avg - expected_avg) < 1e-5, f"Record {i}: Expected avg_response_ms {expected_avg}, got {actual_avg}"

def write_challenge_data(seed):
    rng = random.Random(seed)
    base = datetime(2025 + rng.randrange(0, 8), rng.randrange(1, 13), rng.randrange(1, 25), rng.randrange(0, 24), 0, tzinfo=timezone.utc)
    rows = []
    # Seven populated bins and three gaps. There are exactly three error bins
    # and four no-error bins, so both ranking groups are exercised.
    specs = [
        (0, rng.randrange(12, 22), 0),
        (1, rng.randrange(8, 16), rng.randrange(2, 6)),
        (3, rng.randrange(22, 33), 0),
        (4, rng.randrange(14, 24), rng.randrange(6, 11)),
        (7, rng.randrange(34, 46), 0),
        (8, rng.randrange(18, 29), rng.randrange(11, 17)),
        (9, rng.randrange(6, 12), 0),
    ]
    for bin_number, count, errors in specs:
        for i in range(count):
            ts = base + timedelta(minutes=5 * bin_number, seconds=1 + rng.randrange(0, 298))
            level = 'ERROR' if i < errors else ('WARN' if rng.randrange(0, 5) == 0 else 'INFO')
            response = round(rng.uniform(40.0, 550.0) + bin_number * 0.137, 6)
            rows.append({
                'timestamp': ts.strftime('%Y-%m-%dT%H:%M:%SZ'),
                'level': level,
                'response_ms': response,
            })
    rng.shuffle(rows)
    with open(RAW_LOGS_PATH, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=['timestamp', 'level', 'response_ms'])
        writer.writeheader()
        writer.writerows(rows)

def run_and_check(command):
    if os.path.exists(OUTPUT_JSON_PATH):
        os.remove(OUTPUT_JSON_PATH)
    result = subprocess.run(command, cwd='/home/user', text=True, capture_output=True, timeout=30)
    assert result.returncode == 0, f"Command failed: {command}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert_output_matches_expected()

def test_process_script_exists():
    assert os.path.isfile(PROCESS_PY_PATH), f"Missing processing script: {PROCESS_PY_PATH}"

def test_pipeline_script_exists_and_executable():
    assert os.path.exists(PIPELINE_SH_PATH), f"Missing pipeline script: {PIPELINE_SH_PATH}"
    assert os.access(PIPELINE_SH_PATH, os.X_OK), f"Pipeline script {PIPELINE_SH_PATH} is not executable."

def test_cron_configuration():
    assert os.path.exists(CRON_TXT_PATH), f"Missing cron configuration file: {CRON_TXT_PATH}"
    with open(CRON_TXT_PATH, 'r', encoding='utf-8') as f:
        content = f.read().strip()
    assert content, f"{CRON_TXT_PATH} is empty."
    parts = re.split(r'\s+', content)
    assert len(parts) >= 6, f"Cron expression in {CRON_TXT_PATH} does not have enough fields."
    cron_expr = " ".join(parts[:5])
    command = " ".join(parts[5:])
    assert cron_expr == "0 * * * *", f"Cron expression should be '0 * * * *', got '{cron_expr}'"
    assert PIPELINE_SH_PATH in command, f"Cron command should execute {PIPELINE_SH_PATH}, got '{command}'"

def test_investigation_sample_output_and_execution():
    with open(RAW_LOGS_PATH, 'rb') as f:
        original_raw = f.read()
    try:
        # Preserve the original correctness assertion, but require the wrapper
        # to create the output rather than trusting a prewritten JSON file.
        run_and_check([PIPELINE_SH_PATH])

        # Exercise the Python artifact itself on verifier-generated data.
        write_challenge_data(secrets.randbits(64))
        run_and_check(['python3', PROCESS_PY_PATH])

        # Exercise the wrapper independently on a second unpredictable input.
        write_challenge_data(secrets.randbits(64))
        run_and_check([PIPELINE_SH_PATH])
    finally:
        with open(RAW_LOGS_PATH, 'wb') as f:
            f.write(original_raw)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
