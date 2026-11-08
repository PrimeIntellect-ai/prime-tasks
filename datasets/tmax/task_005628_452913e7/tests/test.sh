#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import secrets
import stat
import subprocess
from pathlib import Path

import pytest


def levenshtein(s1, s2):
    if len(s1) < len(s2):
        return levenshtein(s2, s1)
    if len(s2) == 0:
        return len(s1)
    previous_row = list(range(len(s2) + 1))
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    return previous_row[-1]


def compute_expected_stats(raw_logs_path, sensors_path):
    with open(sensors_path, 'r', encoding='utf-8') as f:
        sensors_data = json.load(f)

    sensor_to_region = {item['sensor_id']: item['region'] for item in sensors_data}

    sensor_messages = {}
    with open(raw_logs_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            sensor_id = row['sensor_id']
            message = row['message']
            if sensor_id not in sensor_messages:
                sensor_messages[sensor_id] = set()
            sensor_messages[sensor_id].add(message)

    region_messages = {}
    for sensor_id, messages in sensor_messages.items():
        region = sensor_to_region.get(sensor_id)
        if region:
            if region not in region_messages:
                region_messages[region] = set()
            region_messages[region].update(messages)

    stats = []
    for region in sorted(region_messages.keys()):
        msgs = list(region_messages[region])
        unique_count = len(msgs)
        if unique_count < 2:
            min_dist = -1
        else:
            min_dist = float('inf')
            for i in range(len(msgs)):
                for j in range(i + 1, len(msgs)):
                    dist = levenshtein(msgs[i], msgs[j])
                    if dist < min_dist:
                        min_dist = dist
        stats.append({
            'region': region,
            'unique_message_count': str(unique_count),
            'min_levenshtein_distance': str(min_dist)
        })
    return stats


def assert_output_matches(output_file, raw_logs_file, sensors_file):
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."
    expected_stats = compute_expected_stats(raw_logs_file, sensors_file)

    with open(output_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        actual_stats = list(reader)

    assert reader.fieldnames == ['region', 'unique_message_count', 'min_levenshtein_distance'], \
        f"CSV headers do not match expected. Got: {reader.fieldnames}"
    assert len(actual_stats) == len(expected_stats), \
        f"Expected {len(expected_stats)} rows, got {len(actual_stats)}"

    for i, (actual, expected) in enumerate(zip(actual_stats, expected_stats)):
        assert actual['region'] == expected['region'], \
            f"Row {i+1}: expected region {expected['region']}, got {actual['region']}"
        assert actual['unique_message_count'] == expected['unique_message_count'], \
            f"Row {i+1} ({expected['region']}): expected unique_message_count {expected['unique_message_count']}, got {actual['unique_message_count']}"
        assert actual['min_levenshtein_distance'] == expected['min_levenshtein_distance'], \
            f"Row {i+1} ({expected['region']}): expected min_levenshtein_distance {expected['min_levenshtein_distance']}, got {actual['min_levenshtein_distance']}"


def test_etl_go_compiles_and_processes_unseen_inputs():
    source = Path('/home/user/etl.go')
    raw_logs = Path('/home/user/raw_logs.csv')
    sensors = Path('/home/user/sensors.json')
    output = Path('/home/user/region_stats.csv')
    binary = Path(f'/tmp/etl_verified_{os.getpid()}')

    assert source.exists(), '/home/user/etl.go does not exist.'
    assert stat.S_ISREG(source.stat().st_mode), '/home/user/etl.go is not a regular file.'
    assert source.stat().st_size > 0, '/home/user/etl.go is empty.'

    build = subprocess.run(
        ['go', 'build', '-o', str(binary), str(source)],
        cwd='/home/user', text=True, capture_output=True, timeout=60
    )
    assert build.returncode == 0, f'etl.go did not compile:\n{build.stdout}\n{build.stderr}'

    original_raw = raw_logs.read_bytes()
    original_sensors = sensors.read_bytes()
    token = secrets.token_hex(8)

    sensor_a1 = f'SA1_{token}'
    sensor_a2 = f'SA2_{token}'
    sensor_b = f'SB_{token}'
    sensor_c = f'SC_{token}'
    unknown = f'UNKNOWN_{token}'
    region_a = f'Alpha_{token}'
    region_b = f'Middle_{token}'
    region_c = f'Zulu_{token}'

    sensor_data = [
        {'sensor_id': sensor_c, 'region': region_c},
        {'sensor_id': sensor_a2, 'region': region_a},
        {'sensor_id': sensor_b, 'region': region_b},
        {'sensor_id': sensor_a1, 'region': region_a},
    ]
    rows = [
        ['1', '2001', sensor_a1, f'Alert-{token}-alpha'],
        ['2', '2002', sensor_a1, f'Alert-{token}-alpha'],
        ['3', '2003', sensor_a1, f'Alert-{token}-alpah'],
        ['4', '2004', sensor_a2, f'Alert-{token}-alpha'],
        ['5', '2005', sensor_a2, f'Pressure,{token},normal'],
        ['6', '2006', sensor_b, f'Only message {token}'],
        ['7', '2007', sensor_c, f'Network-{token}-lost'],
        ['8', '2008', sensor_c, f'Network-{token}-last'],
        ['9', '2009', unknown, f'Ignored-{token}'],
    ]

    try:
        with raw_logs.open('w', encoding='utf-8', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['log_id', 'timestamp', 'sensor_id', 'message'])
            writer.writerows(rows)
        sensors.write_text(json.dumps(sensor_data), encoding='utf-8')
        if output.exists():
            output.unlink()

        run = subprocess.run(
            [str(binary)], cwd='/home/user', text=True,
            capture_output=True, timeout=30
        )
        assert run.returncode == 0, f'Compiled ETL failed on unseen inputs:\n{run.stdout}\n{run.stderr}'
        assert_output_matches(str(output), str(raw_logs), str(sensors))
    finally:
        raw_logs.write_bytes(original_raw)
        sensors.write_bytes(original_sensors)
        if output.exists():
            output.unlink()
        subprocess.run(
            [str(binary)], cwd='/home/user', text=True,
            capture_output=True, timeout=30
        )
        if binary.exists():
            binary.unlink()


def test_region_stats_csv():
    output_file = "/home/user/region_stats.csv"
    raw_logs_file = "/home/user/raw_logs.csv"
    sensors_file = "/home/user/sensors.json"

    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."

    expected_stats = compute_expected_stats(raw_logs_file, sensors_file)

    with open(output_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        actual_stats = list(reader)

    assert reader.fieldnames == ['region', 'unique_message_count', 'min_levenshtein_distance'], \
        f"CSV headers do not match expected. Got: {reader.fieldnames}"

    assert len(actual_stats) == len(expected_stats), \
        f"Expected {len(expected_stats)} rows, got {len(actual_stats)}"

    for i, (actual, expected) in enumerate(zip(actual_stats, expected_stats)):
        assert actual['region'] == expected['region'], \
            f"Row {i+1}: expected region {expected['region']}, got {actual['region']}"
        assert actual['unique_message_count'] == expected['unique_message_count'], \
            f"Row {i+1} ({expected['region']}): expected unique_message_count {expected['unique_message_count']}, got {actual['unique_message_count']}"
        assert actual['min_levenshtein_distance'] == expected['min_levenshtein_distance'], \
            f"Row {i+1} ({expected['region']}): expected min_levenshtein_distance {expected['min_levenshtein_distance']}, got {actual['min_levenshtein_distance']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
