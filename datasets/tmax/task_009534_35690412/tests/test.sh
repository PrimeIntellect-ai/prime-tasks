#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import csv
import json
import math
import statistics
from datetime import datetime, timedelta

INPUT_FILE = '/home/user/input/sensor_data.csv'

# Verifier-owned fixture. Expectations are derived from this constant rather than
# from the mutable input path used by the submitted pipeline.
FIXTURE = [
    {"timestamp": "2023-10-01 10:00:15", "sensor_id": "S1", "temperature": 20.0},
    {"timestamp": "2023-10-01 10:00:45", "sensor_id": "S1", "temperature": 20.2},
    {"timestamp": "2023-10-01 10:01:05", "sensor_id": "S1", "temperature": 20.2},
    {"timestamp": "2023-10-01 10:02:00", "sensor_id": "S1", "temperature": 20.4},
    {"timestamp": "2023-10-01 10:03:00", "sensor_id": "S1", "temperature": 20.5},
    {"timestamp": "2023-10-01 10:04:00", "sensor_id": "S1", "temperature": 20.6},
    {"timestamp": "2023-10-01 10:06:00", "sensor_id": "S1", "temperature": 20.8},
    {"timestamp": "2023-10-01 10:07:00", "sensor_id": "S1", "temperature": 20.9},
    {"timestamp": "2023-10-01 10:08:00", "sensor_id": "S1", "temperature": 21.0},
    {"timestamp": "2023-10-01 10:09:00", "sensor_id": "S1", "temperature": 100.0},
    {"timestamp": "2023-10-01 10:10:00", "sensor_id": "S1", "temperature": 21.2},
    {"timestamp": "2023-10-01 10:11:00", "sensor_id": "S1", "temperature": 21.3},
    {"timestamp": "2023-10-01 10:20:00", "sensor_id": "S1", "temperature": 22.0},
    {"timestamp": "2023-10-01 11:00:00", "sensor_id": "S1", "temperature": 23.0},
    {"timestamp": "2023-10-01 11:01:00", "sensor_id": "S1", "temperature": 23.5},
    {"timestamp": "2023-10-01 09:58:10", "sensor_id": "S2", "temperature": 8.0},
    {"timestamp": "2023-10-01 09:58:50", "sensor_id": "S2", "temperature": 10.0},
    {"timestamp": "2023-10-01 09:59:00", "sensor_id": "S2", "temperature": 9.5},
    {"timestamp": "2023-10-01 10:02:00", "sensor_id": "S2", "temperature": 11.0},
    {"timestamp": "2023-10-01 10:09:00", "sensor_id": "S2", "temperature": 12.4},
    {"timestamp": "2023-10-01 10:10:00", "sensor_id": "S2", "temperature": 12.5},
    {"timestamp": "2023-10-01 11:03:00", "sensor_id": "S2", "temperature": 15.0},
]


def parse_time(ts_str):
    return datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")


def format_time(dt):
    return dt.strftime("%Y-%m-%d %H:%M:%S")


def write_fixture():
    os.makedirs(os.path.dirname(INPUT_FILE), exist_ok=True)
    with open(INPUT_FILE, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=['timestamp', 'sensor_id', 'temperature'])
        writer.writeheader()
        writer.writerows(FIXTURE)


def get_expected_data():
    raw_data = [
        {
            'timestamp': parse_time(row['timestamp']),
            'sensor_id': row['sensor_id'],
            'temperature': float(row['temperature'])
        }
        for row in FIXTURE
    ]

    sensors = {}
    for row in raw_data:
        sensors.setdefault(row['sensor_id'], []).append(row)

    all_anomalies = []
    all_hourly = []

    for sensor_id, rows in sensors.items():
        min_time = min(r['timestamp'] for r in rows).replace(second=0, microsecond=0)
        max_time = max(r['timestamp'] for r in rows).replace(second=0, microsecond=0)

        minute_data = {}
        for row in rows:
            minute = row['timestamp'].replace(second=0, microsecond=0)
            minute_data.setdefault(minute, []).append(row['temperature'])

        resampled = []
        current = min_time
        while current <= max_time:
            values = minute_data.get(current)
            resampled.append({
                'timestamp': current,
                'temperature': (sum(values) / len(values)) if values else None
            })
            current += timedelta(minutes=1)

        # Linear interpolation with a forward limit of five values per bounded
        # gap. For a longer gap, only its first five missing minutes are filled.
        i = 0
        while i < len(resampled):
            if resampled[i]['temperature'] is not None:
                i += 1
                continue
            gap_start = i
            while i < len(resampled) and resampled[i]['temperature'] is None:
                i += 1
            gap_end = i
            prev_idx = gap_start - 1
            next_idx = gap_end
            if prev_idx >= 0 and next_idx < len(resampled):
                gap_size = gap_end - gap_start
                prev_val = resampled[prev_idx]['temperature']
                next_val = resampled[next_idx]['temperature']
                step = (next_val - prev_val) / (gap_size + 1)
                for offset in range(min(5, gap_size)):
                    idx = gap_start + offset
                    resampled[idx]['temperature'] = prev_val + step * (idx - prev_idx)

        anomalies = []
        for i, row in enumerate(resampled):
            window = resampled[max(0, i - 9):i + 1]
            valid_temps = [w['temperature'] for w in window if w['temperature'] is not None]
            if len(valid_temps) >= 3 and row['temperature'] is not None:
                mean = sum(valid_temps) / len(valid_temps)
                std = statistics.stdev(valid_temps)
                if std > 0 and abs(row['temperature'] - mean) > 3 * std:
                    anomalies.append({
                        'timestamp': format_time(row['timestamp']),
                        'sensor_id': sensor_id,
                        'temperature': row['temperature']
                    })
                    row['is_anomaly'] = True

        all_anomalies.extend(anomalies)

        last_valid = None
        for row in resampled:
            if row.get('is_anomaly'):
                row['temperature'] = last_valid
            elif row['temperature'] is not None:
                last_valid = row['temperature']
            elif last_valid is not None:
                row['temperature'] = last_valid

        hourly_data = {}
        for row in resampled:
            if row['temperature'] is not None:
                hour = row['timestamp'].replace(minute=0, second=0, microsecond=0)
                hourly_data.setdefault(hour, []).append(row['temperature'])

        for hour, temps in hourly_data.items():
            all_hourly.append({
                'timestamp': format_time(hour),
                'sensor_id': sensor_id,
                'mean_temp': sum(temps) / len(temps),
                'min_temp': min(temps),
                'max_temp': max(temps)
            })

    all_anomalies.sort(key=lambda x: (x['timestamp'], x['sensor_id']))
    all_hourly.sort(key=lambda x: (x['timestamp'], x['sensor_id']))
    return all_anomalies, all_hourly


def test_anomalies_json():
    expected_anomalies, _ = get_expected_data()
    output_file = '/home/user/output/anomalies.json'

    assert os.path.isfile(output_file) and not os.path.islink(output_file), \
        f"Output file {output_file} does not exist or is not a regular file."

    with open(output_file, 'r') as f:
        try:
            actual_anomalies = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{output_file} is not a valid JSON file."

    assert isinstance(actual_anomalies, list), f"{output_file} should contain a JSON list."
    assert len(actual_anomalies) == len(expected_anomalies), \
        f"Expected {len(expected_anomalies)} anomalies, but found {len(actual_anomalies)}."

    for actual, expected in zip(actual_anomalies, expected_anomalies):
        assert isinstance(actual, dict)
        assert set(actual) == {'timestamp', 'sensor_id', 'temperature'}, \
            f"Anomaly entries must contain exactly timestamp, sensor_id, and temperature: {actual}"
        assert actual['timestamp'] == expected['timestamp'], \
            f"Timestamp mismatch: expected {expected['timestamp']}, got {actual['timestamp']}"
        assert actual['sensor_id'] == expected['sensor_id'], \
            f"Sensor ID mismatch: expected {expected['sensor_id']}, got {actual['sensor_id']}"
        assert math.isclose(float(actual['temperature']), expected['temperature'], rel_tol=1e-5), \
            f"Temperature mismatch for {expected['timestamp']}: expected {expected['temperature']}, got {actual['temperature']}"


def test_hourly_stats_csv():
    _, expected_hourly = get_expected_data()
    output_file = '/home/user/output/hourly_stats.csv'

    assert os.path.isfile(output_file) and not os.path.islink(output_file), \
        f"Output file {output_file} does not exist or is not a regular file."

    with open(output_file, 'r', newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['timestamp', 'sensor_id', 'mean_temp', 'min_temp', 'max_temp'], \
            f"Unexpected CSV columns: {reader.fieldnames}"
        actual_hourly = list(reader)

    assert len(actual_hourly) == len(expected_hourly), \
        f"Expected {len(expected_hourly)} hourly records, but found {len(actual_hourly)}."

    for actual, expected in zip(actual_hourly, expected_hourly):
        assert actual['timestamp'] == expected['timestamp'], \
            f"Timestamp mismatch: expected {expected['timestamp']}, got {actual['timestamp']}"
        assert actual['sensor_id'] == expected['sensor_id'], \
            f"Sensor ID mismatch: expected {expected['sensor_id']}, got {actual['sensor_id']}"

        expected_mean = f"{expected['mean_temp']:.2f}"
        expected_min = f"{expected['min_temp']:.2f}"
        expected_max = f"{expected['max_temp']:.2f}"
        assert actual['mean_temp'] == expected_mean, \
            f"mean_temp mismatch: expected {expected_mean}, got {actual['mean_temp']}"
        assert actual['min_temp'] == expected_min, \
            f"min_temp mismatch: expected {expected_min}, got {actual['min_temp']}"
        assert actual['max_temp'] == expected_max, \
            f"max_temp mismatch: expected {expected_max}, got {actual['max_temp']}"


if __name__ == '__main__' and len(sys.argv) == 2 and sys.argv[1] == '--write-input':
    write_fixture()
TEST_EOF

if (
    set -e
    test -f /home/user/process_pipeline.py
    test ! -L /home/user/process_pipeline.py

    rm -rf /home/user/input /home/user/output
    mkdir -p /home/user/input /home/user/output
    chown user:user /home/user/output
    chmod 755 /home/user/input
    chmod 777 /home/user/output

    python3 /tmp/test_final_state.py --write-input
    chown root:root /home/user/input/sensor_data.csv
    chmod 444 /home/user/input/sensor_data.csv

    rm -f /home/user/output/anomalies.json /home/user/output/hourly_stats.csv
    timeout 60s runuser -u user -- bash -c 'cd /home/user && python3 /home/user/process_pipeline.py'

    python3 -m pytest /tmp/test_final_state.py -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
