#!/bin/bash
set +e
mkdir -p /logs/verifier
status=0

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest

def test_processed_directory_exists():
    assert os.path.isdir('/home/user/processed'), "The directory /home/user/processed was not created."

def test_clean_data_json():
    filepath = '/home/user/processed/clean_data.json'
    assert os.path.isfile(filepath), f"The file {filepath} was not created."

    with open(filepath, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {filepath} does not contain valid JSON.")

    assert isinstance(data, list), f"{filepath} must contain a JSON array."

    expected_data = [
        {"tx_id": "T001", "timestamp": "2023-10-01T10:00:00Z", "user_id": "U1", "amount": 100.0},
        {"tx_id": "T002", "timestamp": "2023-10-01T12:00:00Z", "user_id": "U2", "amount": 150.0},
        {"tx_id": "T003", "timestamp": "2023-10-02T10:00:00Z", "user_id": "U1", "amount": 120.0},
        {"tx_id": "T004", "timestamp": "2023-10-02T10:00:00Z", "user_id": "U3", "amount": 400.0},
        {"tx_id": "T005", "timestamp": "2023-10-03T11:00:00Z", "user_id": "U4", "amount": 260.0}
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records in {filepath}, but found {len(data)}."

    for i, expected_record in enumerate(expected_data):
        actual_record = data[i]
        assert actual_record.get("tx_id") == expected_record["tx_id"], f"Record {i} tx_id mismatch."
        assert actual_record.get("timestamp") == expected_record["timestamp"], f"Record {i} timestamp mismatch."
        assert actual_record.get("user_id") == expected_record["user_id"], f"Record {i} user_id mismatch."
        assert float(actual_record.get("amount", 0)) == expected_record["amount"], f"Record {i} amount mismatch."

def test_anomalies_json():
    filepath = '/home/user/processed/anomalies.json'
    assert os.path.isfile(filepath), f"The file {filepath} was not created."

    with open(filepath, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {filepath} does not contain valid JSON.")

    assert isinstance(data, list), f"{filepath} must contain a JSON array."

    expected_anomalies = [
        {
            "date": "2023-10-02",
            "previous_avg": 125.0,
            "current_avg": 260.0,
            "deviation_pct": 108.0
        }
    ]

    assert len(data) == len(expected_anomalies), f"Expected {len(expected_anomalies)} anomalies in {filepath}, but found {len(data)}."

    for i, expected_record in enumerate(expected_anomalies):
        actual_record = data[i]
        assert actual_record.get("date") == expected_record["date"], f"Anomaly {i} date mismatch."
        assert float(actual_record.get("previous_avg", 0)) == expected_record["previous_avg"], f"Anomaly {i} previous_avg mismatch."
        assert float(actual_record.get("current_avg", 0)) == expected_record["current_avg"], f"Anomaly {i} current_avg mismatch."

        actual_deviation = float(actual_record.get("deviation_pct", 0))
        assert abs(actual_deviation - expected_record["deviation_pct"]) < 0.1, f"Anomaly {i} deviation_pct mismatch. Expected {expected_record['deviation_pct']}, got {actual_deviation}."

def test_go_program_exists():
    assert os.path.isfile('/home/user/etl_pipeline.go'), "The Go program /home/user/etl_pipeline.go is missing."
TEST_EOF

# Execute the submitted artifact against the original data before retaining the
# original final-state assertions.
if [ ! -f /home/user/etl_pipeline.go ]; then
    status=1
else
    rm -rf /home/user/processed
    (cd /home/user && timeout 90s go run /home/user/etl_pipeline.go) || status=1
fi

if [ "$status" -eq 0 ]; then
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || status=1
fi

# Build a fresh randomized input and derive its expected result independently.
if [ "$status" -eq 0 ]; then
python3 << 'GEN_EOF' || status=1
import csv
import glob
import json
import os
import random
import secrets
from collections import defaultdict
from datetime import datetime, timedelta, timezone

raw = '/home/user/raw_data'
os.makedirs(raw, exist_ok=True)
for path in glob.glob(os.path.join(raw, '*')):
    if os.path.isfile(path):
        os.remove(path)

prefix = secrets.token_hex(4).upper()
base = float(random.SystemRandom().randrange(4, 16) * 20)
start = datetime(2024, 1, 1, tzinfo=timezone.utc) + timedelta(days=random.SystemRandom().randrange(0, 300))

def stamp(day, hour):
    return (start + timedelta(days=day, hours=hour)).strftime('%Y-%m-%dT%H:%M:%SZ')

a, b, c, d, e = [prefix + suffix for suffix in ('A', 'B', 'C', 'D', 'E')]
batches = [
    [
        [a, stamp(0, 8), 'old-user', base * 9],
        [b, stamp(0, 10), 'user-b', base],
        [c, stamp(0, 7), 'old-c', base * 3],
    ],
    [
        [a, stamp(0, 12), 'user-a', base],
        [c, stamp(1, 9), 'user-c', base * 1.5],
        [d, stamp(2, 11), 'user-d', base * 0.6],
    ],
    [
        [a, stamp(0, 9), 'middle-user', base * 4],
        [e, stamp(2, 13), 'user-e', base * 0.6],
    ],
]
random.SystemRandom().shuffle(batches)
for i, rows in enumerate(batches):
    random.SystemRandom().shuffle(rows)
    path = os.path.join(raw, f'{prefix}_{i}_{secrets.token_hex(2)}.csv')
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['tx_id', 'timestamp', 'user_id', 'amount'])
        writer.writerows(rows)

# Independently derive the oracle from the generated CSV files.
latest = {}
for path in glob.glob(os.path.join(raw, '*.csv')):
    with open(path, newline='') as f:
        for row in csv.DictReader(f):
            record = {
                'tx_id': row['tx_id'],
                'timestamp': row['timestamp'],
                'user_id': row['user_id'],
                'amount': float(row['amount']),
            }
            parsed = datetime.fromisoformat(record['timestamp'].replace('Z', '+00:00'))
            old = latest.get(record['tx_id'])
            if old is None or parsed > old[0]:
                latest[record['tx_id']] = (parsed, record)

clean = [latest[key][1] for key in sorted(latest)]
amounts = defaultdict(list)
for record in clean:
    amounts[record['timestamp'][:10]].append(record['amount'])
averages = {day: sum(values) / len(values) for day, values in amounts.items()}
anomalies = []
days = sorted(averages)
for previous_day, current_day in zip(days, days[1:]):
    previous = averages[previous_day]
    current = averages[current_day]
    deviation = abs(current - previous) / previous
    if deviation > 0.50:
        anomalies.append({
            'date': current_day,
            'previous_avg': previous,
            'current_avg': current,
            'deviation_pct': deviation * 100.0,
        })

with open('/tmp/dynamic_expected.json', 'w') as f:
    json.dump({'clean': clean, 'anomalies': anomalies}, f)
GEN_EOF
fi

if [ "$status" -eq 0 ]; then
    rm -rf /home/user/processed
    (cd /home/user && timeout 90s go run /home/user/etl_pipeline.go) || status=1
fi

if [ "$status" -eq 0 ]; then
python3 << 'CHECK_EOF' || status=1
import json
import os

assert os.path.isdir('/home/user/processed'), 'The program did not create /home/user/processed on fresh input.'
with open('/tmp/dynamic_expected.json') as f:
    expected = json.load(f)
with open('/home/user/processed/clean_data.json') as f:
    clean = json.load(f)
with open('/home/user/processed/anomalies.json') as f:
    anomalies = json.load(f)

assert isinstance(clean, list), 'clean_data.json must contain a JSON array.'
assert isinstance(anomalies, list), 'anomalies.json must contain a JSON array.'
assert len(clean) == len(expected['clean']), 'Incorrect number of deduplicated records on fresh input.'
for index, (actual, wanted) in enumerate(zip(clean, expected['clean'])):
    assert actual.get('tx_id') == wanted['tx_id'], f'Record {index} tx_id or sorting mismatch.'
    assert actual.get('timestamp') == wanted['timestamp'], f'Record {index} did not retain the latest timestamp.'
    assert actual.get('user_id') == wanted['user_id'], f'Record {index} user_id mismatch.'
    assert abs(float(actual.get('amount')) - wanted['amount']) < 1e-9, f'Record {index} amount mismatch.'

assert len(anomalies) == len(expected['anomalies']), 'Incorrect anomaly count on fresh input.'
for index, (actual, wanted) in enumerate(zip(anomalies, expected['anomalies'])):
    assert actual.get('date') == wanted['date'], f'Anomaly {index} date or ordering mismatch.'
    assert abs(float(actual.get('previous_avg')) - wanted['previous_avg']) < 1e-7, f'Anomaly {index} previous_avg mismatch.'
    assert abs(float(actual.get('current_avg')) - wanted['current_avg']) < 1e-7, f'Anomaly {index} current_avg mismatch.'
    assert abs(float(actual.get('deviation_pct')) - wanted['deviation_pct']) < 0.1, f'Anomaly {index} deviation_pct mismatch.'
CHECK_EOF
fi

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
