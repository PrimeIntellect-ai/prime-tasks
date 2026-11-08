#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import subprocess
import re

SOURCE = "/home/user/etl_processor.cpp"
BINARY = "/home/user/etl_processor"
RAW = "/home/user/raw_sensor_data.csv"
RESAMPLED = "/home/user/resampled.csv"
DISTANCE = "/home/user/distance.txt"


def get_expected_data():
    assert os.path.exists(RAW), f"Input file {RAW} is missing."
    sensor_data = {"S1": {}, "S2": {}}
    with open(RAW, newline='') as f:
        for row in csv.reader(f):
            if not row:
                continue
            assert len(row) == 3
            t, sensor, value = int(row[0]), row[1], float(row[2])
            if sensor in sensor_data:
                old = sensor_data[sensor].get(t)
                if old is None or value > old:
                    sensor_data[sensor][t] = value

    all_timestamps = [t for values in sensor_data.values() for t in values]
    assert all_timestamps
    t_min, t_max = min(all_timestamps), max(all_timestamps)

    def interpolate(data):
        assert data
        keys = sorted(data)
        result = {}
        for t in range(t_min, t_max + 1):
            if t in data:
                result[t] = data[t]
            elif t < keys[0]:
                result[t] = data[keys[0]]
            elif t > keys[-1]:
                result[t] = data[keys[-1]]
            else:
                prev_t = max(k for k in keys if k < t)
                next_t = min(k for k in keys if k > t)
                result[t] = data[prev_t] + (data[next_t] - data[prev_t]) * (t - prev_t) / (next_t - prev_t)
        return result

    s1 = interpolate(sensor_data["S1"])
    s2 = interpolate(sensor_data["S2"])
    distance = math.sqrt(sum((s1[t] - s2[t]) ** 2 for t in range(t_min, t_max + 1)))
    return t_min, t_max, s1, s2, distance


def test_program_exists_compiles_and_runs():
    assert os.path.isfile(SOURCE), f"Required source file {SOURCE} is missing."
    source_text = open(SOURCE, encoding='utf-8', errors='replace').read()
    assert re.search(r'\bstd::thread\b|\bstd::async\b|#\s*pragma\s+omp\b', source_text), "No C++ parallel processing mechanism found."
    subprocess.run(["g++", "-std=c++17", "-pthread", SOURCE, "-o", BINARY], check=True, timeout=30)
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)
    for path in (RESAMPLED, DISTANCE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    subprocess.run([BINARY], cwd="/home/user", check=True, timeout=30)


def test_resampled_csv():
    assert os.path.exists(RESAMPLED), f"Output file {RESAMPLED} is missing."
    t_min, t_max, s1_resampled, s2_resampled, _ = get_expected_data()
    with open(RESAMPLED, newline='') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['timestamp', 'S1_value', 'S2_value'], f"Incorrect header in {RESAMPLED}."
        rows = list(reader)

    expected_timestamps = list(range(t_min, t_max + 1))
    assert len(rows) == len(expected_timestamps), f"Expected {len(expected_timestamps)} rows, got {len(rows)}."
    actual_timestamps = []
    for row in rows:
        assert len(row) == 3, f"Row {row} does not have 3 columns."
        t = int(row[0])
        actual_timestamps.append(t)
        v1_str, v2_str = row[1], row[2]
        assert re.fullmatch(r'-?\d+\.\d{4}', v1_str), f"S1_value {v1_str} not formatted to exactly 4 decimal places."
        assert re.fullmatch(r'-?\d+\.\d{4}', v2_str), f"S2_value {v2_str} not formatted to exactly 4 decimal places."
        v1, v2 = float(v1_str), float(v2_str)
        assert t in s1_resampled, f"Unexpected timestamp {t}."
        assert abs(v1 - s1_resampled[t]) < 1e-3, f"S1 value at {t} is incorrect."
        assert abs(v2 - s2_resampled[t]) < 1e-3, f"S2 value at {t} is incorrect."
    assert actual_timestamps == expected_timestamps, "Timestamps must occur exactly once in increasing one-second intervals."


def test_distance_txt():
    assert os.path.exists(DISTANCE), f"Output file {DISTANCE} is missing."
    _, _, _, _, expected_distance = get_expected_data()
    with open(DISTANCE) as f:
        content = f.read().strip()
    assert re.fullmatch(r'-?\d+\.\d{4}', content), f"Distance {content} not formatted to exactly 4 decimal places."
    assert abs(float(content) - expected_distance) < 1e-3, f"Distance is incorrect. Expected {expected_distance}, got {content}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
