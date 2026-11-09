#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import hashlib
from decimal import Decimal, ROUND_HALF_UP
from datetime import datetime, timedelta, timezone

ALPHA_PATH = '/home/user/data/stream_alpha.csv'
BETA_PATH = '/home/user/data/stream_beta.csv'
OUTPUT_PATH = '/home/user/output/clean_sensors.jsonl'

EXPECTED_ALPHA = b'''timestamp,device_id,sensor_value,error_code
2023/10/01 10:00:00,DEV_A,45.23,0
2023/10/01 10:05:00,DEV_A,45.21,0
2023/10/01 10:10:00,DEV_B,-60.0,0
2023/10/01 10:15:00,DEV_C,100.0,1
2023/10/01 11:00:00,DEV_D,149.99,0
'''
EXPECTED_BETA = b'''ts,dev,val,err
1696172400,DEV_A,45.25,0
1696176000,DEV_E,0.0,0
1696176060,DEV_E,0.04,0
1696180000,DEV_F,200.0,0
'''

def assert_inputs_intact():
    assert os.path.isfile(ALPHA_PATH), f'Required input file {ALPHA_PATH} is missing.'
    assert os.path.isfile(BETA_PATH), f'Required input file {BETA_PATH} is missing.'
    with open(ALPHA_PATH, 'rb') as f:
        assert f.read() == EXPECTED_ALPHA, f'Required input file {ALPHA_PATH} was modified.'
    with open(BETA_PATH, 'rb') as f:
        assert f.read() == EXPECTED_BETA, f'Required input file {BETA_PATH} was modified.'

def compute_expected_data(rounding_mode):
    assert_inputs_intact()
    records = []

    with open(ALPHA_PATH, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            dt_local = datetime.strptime(row['timestamp'], '%Y/%m/%d %H:%M:%S')
            dt_utc = (dt_local + timedelta(hours=4)).replace(tzinfo=timezone.utc)
            records.append({
                'timestamp_dt': dt_utc,
                'device_id': row['device_id'],
                'sensor_value': float(row['sensor_value']),
                'sensor_text': row['sensor_value'],
                'error_code': int(row['error_code'])
            })

    with open(BETA_PATH, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            dt_utc = datetime.fromtimestamp(int(row['ts']), tz=timezone.utc)
            records.append({
                'timestamp_dt': dt_utc,
                'device_id': row['dev'],
                'sensor_value': float(row['val']),
                'sensor_text': row['val'],
                'error_code': int(row['err'])
            })

    valid_records = [
        r for r in records
        if -50.0 <= r['sensor_value'] <= 150.0 and r['error_code'] == 0
    ]

    dedup = {}
    for r in valid_records:
        if rounding_mode == 'python':
            rounded_val = round(r['sensor_value'], 1)
        else:
            rounded_val = float(Decimal(r['sensor_text']).quantize(Decimal('0.1'), rounding=ROUND_HALF_UP))

        hash_str = f"{r['device_id']}_{rounded_val:.1f}"
        md5_hash = hashlib.md5(hash_str.encode('utf-8')).hexdigest()
        candidate = dict(r)
        candidate['hash'] = md5_hash
        candidate['rounded_val'] = rounded_val

        if md5_hash not in dedup or candidate['timestamp_dt'] < dedup[md5_hash]['timestamp_dt']:
            dedup[md5_hash] = candidate

    final_records = list(dedup.values())
    final_records.sort(key=lambda x: (x['timestamp_dt'], x['device_id']))
    return [{
        'timestamp': r['timestamp_dt'].strftime('%Y-%m-%dT%H:%M:%SZ'),
        'device_id': r['device_id'],
        'sensor_value': r['rounded_val'],
        'hash': r['hash']
    } for r in final_records]

def test_input_files_are_present_and_unchanged():
    assert_inputs_intact()

def test_output_file_exists():
    assert os.path.isfile(OUTPUT_PATH), f'Expected output file {OUTPUT_PATH} does not exist.'

def test_output_file_contents():
    assert_inputs_intact()
    assert os.path.isfile(OUTPUT_PATH), f'Output file {OUTPUT_PATH} is missing.'

    actual_records = []
    with open(OUTPUT_PATH, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                actual_records.append(record)
            except json.JSONDecodeError:
                assert False, f'Line {line_num} in {OUTPUT_PATH} is not valid JSON.'

    for i, actual in enumerate(actual_records):
        assert isinstance(actual, dict), f'Record {i+1} is not a JSON object.'
        assert set(actual.keys()) == {'timestamp', 'device_id', 'sensor_value', 'hash'}, (
            f'Record {i+1} has incorrect keys. Expected exact keys: '
            'timestamp, device_id, sensor_value, hash.'
        )

    # The instruction does not define how an exact decimal tie such as 45.25 is
    # broken. Accept both common interpretations: ties-to-even and half-up.
    candidates = [
        compute_expected_data('python'),
        compute_expected_data('half_up')
    ]
    candidates = [c for i, c in enumerate(candidates) if c not in candidates[:i]]

    matching_lengths = [c for c in candidates if len(c) == len(actual_records)]
    assert matching_lengths, (
        f'Expected one of {[len(c) for c in candidates]} records, but found '
        f'{len(actual_records)}. Check your filtering and deduplication logic.'
    )

    expected = next((c for c in matching_lengths if c == actual_records), matching_lengths[0])
    for i, (actual, exp) in enumerate(zip(actual_records, expected)):
        assert actual['timestamp'] == exp['timestamp'], (
            f"Record {i+1} timestamp mismatch. Expected {exp['timestamp']}, got {actual['timestamp']}."
        )
        assert actual['device_id'] == exp['device_id'], (
            f"Record {i+1} device_id mismatch. Expected {exp['device_id']}, got {actual['device_id']}."
        )
        assert actual['sensor_value'] == exp['sensor_value'], (
            f"Record {i+1} sensor_value mismatch. Expected {exp['sensor_value']}, got {actual['sensor_value']}."
        )
        assert actual['hash'] == exp['hash'], (
            f"Record {i+1} hash mismatch. Expected {exp['hash']}, got {actual['hash']}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
