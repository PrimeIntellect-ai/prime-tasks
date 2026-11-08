#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import hashlib
from datetime import datetime, timedelta

EXPECTED_INPUT_ROWS = [
    ("2023-10-01T08:00:00Z", "dev-a", "dev", "debug=true;port=8080"),
    ("2023-10-02T09:00:00Z", "dev-a", "dev", "debug=true;port=8080"),
    ("2023-10-04T10:00:00Z", "dev-a", "dev", "debug=false;port=8080"),
    ("2023-10-01T12:00:00Z", "dev-b", "dev", "debug=true;port=8081"),
    ("2023-10-05T12:00:00Z", "dev-c", "dev", "debug=true;port=8082"),
    ("2023-09-28T10:00:00Z", "prod-a", "prod", "workers=4;timeout=30"),
    ("2023-10-03T14:00:00Z", "prod-a", "prod", "workers=8;timeout=30"),
    ("2023-10-03T16:00:00Z", "prod-a", "prod", "workers=8;timeout=60"),
    ("2023-10-01T00:00:00Z", "prod-b", "prod", "workers=4;timeout=30"),
    ("2023-10-06T00:00:00Z", "prod-b", "prod", "workers=4;timeout=30"),
    ("2023-10-01T11:00:00Z", "prod-c", "prod", "workers=4;timeout=30"),
    ("2023-10-02T10:00:00Z", "stage-a", "staging", "cache=redis;ttl=3600"),
]

TRUSTED_INPUT = "/tmp/trusted_config_history.csv"
with open(TRUSTED_INPUT, "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["timestamp", "server_name", "environment", "config_text"])
    writer.writerows(EXPECTED_INPUT_ROWS)


def compute_expected_state(input_path):
    if not os.path.exists(input_path):
        return []

    with open(input_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    servers = {}
    env_servers = {}
    for row in rows:
        env = row['environment']
        srv = row['server_name']
        dt = row['timestamp']
        text = row['config_text']

        if env not in env_servers:
            env_servers[env] = set()
        env_servers[env].add(srv)

        if srv not in servers:
            servers[srv] = []
        servers[srv].append((dt, text, env))

    sampled_servers = set()
    for env, srv_set in env_servers.items():
        sorted_srvs = sorted(list(srv_set))
        sampled_servers.update(sorted_srvs[:2])

    start_date = datetime(2023, 10, 1)
    end_date = datetime(2023, 10, 7)
    expected_rows = []

    for srv in sampled_servers:
        srv_configs = servers[srv]
        env = srv_configs[0][2]
        srv_configs.sort(key=lambda x: x[0])

        for day_offset in range(8):
            current_date = start_date + timedelta(days=day_offset)
            if current_date > end_date:
                break

            date_str = current_date.strftime('%Y-%m-%d')
            current_date_end = date_str + "T23:59:59Z"
            latest_text = None
            for dt, text, _ in srv_configs:
                if dt <= current_date_end:
                    latest_text = text

            if latest_text is None:
                config_hash = "NO_CONFIG"
            else:
                config_hash = hashlib.md5(latest_text.encode('utf-8')).hexdigest()

            expected_rows.append({
                'date': date_str,
                'server_name': srv,
                'environment': env,
                'config_hash': config_hash
            })

    expected_rows.sort(key=lambda x: (x['environment'], x['server_name'], x['date']))
    return expected_rows


def test_input_data_is_present_and_unchanged():
    input_path = "/home/user/config_history.csv"
    assert os.path.isfile(input_path), f"Expected input file {input_path} does not exist."

    with open(input_path, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert rows, "Input CSV is empty."
    assert rows[0] == ['timestamp', 'server_name', 'environment', 'config_text'], \
        f"Input CSV headers were changed: {rows[0]}"
    assert [tuple(row) for row in rows[1:]] == EXPECTED_INPUT_ROWS, \
        "Input CSV contents were deleted or modified."


def test_stratified_config_timeline_exists():
    output_path = "/home/user/stratified_config_timeline.csv"
    assert os.path.isfile(output_path), f"Expected output file {output_path} does not exist."


def test_stratified_config_timeline_content():
    output_path = "/home/user/stratified_config_timeline.csv"
    expected_rows = compute_expected_state(TRUSTED_INPUT)

    with open(output_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        actual_rows = list(reader)

    assert reader.fieldnames == ['date', 'server_name', 'environment', 'config_hash'], \
        f"CSV headers are incorrect. Expected ['date', 'server_name', 'environment', 'config_hash'], got {reader.fieldnames}"

    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows, but got {len(actual_rows)} rows in the output CSV."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual['date'] == expected['date'], f"Row {i+1}: Expected date {expected['date']}, got {actual['date']}"
        assert actual['server_name'] == expected['server_name'], f"Row {i+1}: Expected server_name {expected['server_name']}, got {actual['server_name']}"
        assert actual['environment'] == expected['environment'], f"Row {i+1}: Expected environment {expected['environment']}, got {actual['environment']}"
        assert actual['config_hash'] == expected['config_hash'], f"Row {i+1}: Server {actual['server_name']} on {actual['date']} expected hash {expected['config_hash']}, got {actual['config_hash']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
