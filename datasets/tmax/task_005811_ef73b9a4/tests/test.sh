#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
from datetime import datetime, timezone

def parse_timestamp(ts):
    if isinstance(ts, (int, float)):
        return datetime.fromtimestamp(ts, tz=timezone.utc)
    elif isinstance(ts, str):
        if ts.endswith('Z'):
            return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        else:
            dt = datetime.strptime(ts, "%Y-%m-%d %H:%M:%S %z")
            return dt.astimezone(timezone.utc)
    raise ValueError(f"Unknown timestamp format: {ts}")

def format_timestamp(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

def compute_expected_drifts(input_file):
    with open(input_file, 'r') as f:
        records = [json.loads(line) for line in f if line.strip()]

    # Parse timestamps
    for r in records:
        r['_dt'] = parse_timestamp(r['timestamp'])

    # Group by host
    hosts = {}
    for r in records:
        hosts.setdefault(r['host'], []).append(r)

    drifts = []
    parameters = ['cpu_cores', 'max_conns', 'ram_gb']

    for host, host_records in hosts.items():
        # Sort chronologically
        host_records.sort(key=lambda x: x['_dt'])

        if not host_records:
            continue

        # Baseline
        baseline = host_records[0]
        current_state = {p: baseline[p] for p in parameters}

        for r in host_records[1:]:
            for p in parameters:
                if r[p] != current_state[p]:
                    drifts.append({
                        'host': host,
                        'timestamp': format_timestamp(r['_dt']),
                        'parameter': p,
                        'old_value': str(current_state[p]),
                        'new_value': str(r[p])
                    })
                    current_state[p] = r[p]

    # Sort drifts
    drifts.sort(key=lambda x: (x['host'], x['timestamp'], x['parameter']))
    return drifts

def test_config_drifts_csv():
    input_file = '/home/user/raw_configs.jsonl'
    output_file = '/home/user/config_drifts.csv'

    assert os.path.exists(output_file), f"Output file {output_file} does not exist."

    expected_drifts = compute_expected_drifts(input_file)

    actual_drifts = []
    with open(output_file, 'r', newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['host', 'timestamp', 'parameter', 'old_value', 'new_value'], \
            f"CSV header is incorrect. Got: {reader.fieldnames}"
        for row in reader:
            actual_drifts.append(row)

    assert len(actual_drifts) == len(expected_drifts), \
        f"Expected {len(expected_drifts)} drift records, but got {len(actual_drifts)}."

    for i, (actual, expected) in enumerate(zip(actual_drifts, expected_drifts)):
        assert actual == expected, \
            f"Mismatch at row {i + 1} (1-indexed after header).\nExpected: {expected}\nActual: {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
