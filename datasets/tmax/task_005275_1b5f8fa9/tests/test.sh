#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import subprocess
from pathlib import Path

import pytest

ROOT = Path('/home/user')
PROJECT = ROOT / 'sensor_analysis'
OUTPUT = ROOT / 'analysis_output.json'
LOCATIONS = ROOT / 'locations.txt'
READINGS = ROOT / 'readings.csv'

ORIGINAL_LOCATIONS = '''Field report from January.
Sensor S1 is installed at origin (0.0, 0.0).
We moved S2 to (3.0, 4.0) yesterday after the storm.
S3 was found at (1.0, 1.0) partially covered in mud.
'''

ORIGINAL_READINGS = '''hour,sensor,temperature
0,S1,10.0
1,S1,12.0
3,S1,14.0
9,S1,20.0
0,S2,100.0
2,S2,120.0
4,S2,140.0
9,S2,200.0
0,S3,5.0
1,S3,5.0
5,S3,10.0
'''


def run_submission():
    assert PROJECT.is_dir(), f'Missing Rust project directory: {PROJECT}'
    manifest = PROJECT / 'Cargo.toml'
    source = PROJECT / 'src' / 'main.rs'
    assert manifest.is_file(), f'Missing Cargo manifest: {manifest}'
    assert source.is_file(), f'Missing Rust entry point: {source}'
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        ['cargo', 'run', '--quiet', '--manifest-path', str(manifest)],
        cwd=str(PROJECT), text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=180
    )
    assert result.returncode == 0, (
        f'Rust program failed with exit code {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert OUTPUT.exists(), f'Missing expected output file: {OUTPUT}'
    assert OUTPUT.is_file(), f'Expected a file, but found a directory: {OUTPUT}'
    try:
        with OUTPUT.open() as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f'Failed to parse JSON from {OUTPUT}: {e}')


def assert_shape(data):
    expected_keys = {'most_similar_profiles', 'profile_distance', 'spatial_distance'}
    assert set(data.keys()) == expected_keys, f'JSON keys do not match expected. Found: {list(data.keys())}'
    profiles = data['most_similar_profiles']
    assert isinstance(profiles, list), 'most_similar_profiles must be a list'
    assert len(profiles) == 2 and all(isinstance(x, str) for x in profiles)
    for key in ('profile_distance', 'spatial_distance'):
        value = data[key]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), f'{key} must be a number'
        assert math.isfinite(value), f'{key} must be finite'


def derive_expected(coordinates, rows):
    sensors = sorted(coordinates)
    by_sensor = {sensor: {} for sensor in sensors}
    for hour, sensor, temperature in rows:
        by_sensor[sensor][hour] = temperature

    standardized = {}
    for sensor in sensors:
        assert 0 in by_sensor[sensor]
        profile = []
        current = None
        for hour in range(10):
            if hour in by_sensor[sensor]:
                current = by_sensor[sensor][hour]
            profile.append(current)
        mean = sum(profile) / 10.0
        std = math.sqrt(sum((x - mean) ** 2 for x in profile) / 10.0)
        assert std > 0
        standardized[sensor] = [(x - mean) / std for x in profile]

    candidates = []
    for i, left in enumerate(sensors):
        for right in sensors[i + 1:]:
            profile_distance = math.sqrt(sum(
                (a - b) ** 2 for a, b in zip(standardized[left], standardized[right])
            ))
            candidates.append((profile_distance, left, right))
    distance, left, right = min(candidates, key=lambda item: (item[0], item[1], item[2]))
    x1, y1 = coordinates[left]
    x2, y2 = coordinates[right]
    spatial = math.hypot(x1 - x2, y1 - y2)
    return [left, right], round(distance, 4), round(spatial, 4)


def write_random_fixture():
    rng = random.SystemRandom()
    sensors = ['S11', 'S24', 'S37', 'S49', 'S58']
    coordinates = {}
    location_lines = ['Unstructured deployment notes follow.']
    for sensor in sensors:
        x = rng.randint(-150, 150) / 10.0
        y = rng.randint(-150, 150) / 10.0
        coordinates[sensor] = (x, y)
        location_lines.append(f'After inspection, unit {sensor} was recorded near ({x:.1f}, {y:.1f}) despite the weather.')

    matching_pair = rng.sample(sensors, 2)
    shared_hours = [0, 1, 3, 6, 9]
    base_values = [rng.uniform(-20, 10), rng.uniform(11, 25), rng.uniform(-5, 8), rng.uniform(28, 45), rng.uniform(5, 18)]
    scale = rng.uniform(1.5, 4.0)
    offset = rng.uniform(40, 100)

    rows = []
    for index, sensor in enumerate(sensors):
        if sensor == matching_pair[0]:
            hours = shared_hours
            values = base_values
        elif sensor == matching_pair[1]:
            hours = shared_hours
            values = [scale * value + offset for value in base_values]
        else:
            hours = sorted({0, 2 + (index % 2), 5 + (index % 3), 8, 9})
            values = [
                rng.uniform(-30, 50) + (j * j * (index + 1)) + (7 if j % 2 else -4)
                for j in range(len(hours))
            ]
        for hour, value in zip(hours, values):
            rows.append((hour, sensor, value))

    rng.shuffle(rows)
    LOCATIONS.write_text('\n'.join(location_lines) + '\n')
    with READINGS.open('w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        writer.writerow(['hour', 'sensor', 'temperature'])
        for hour, sensor, value in rows:
            writer.writerow([hour, sensor, f'{value:.10f}'])

    rounded_rows = [(h, s, float(f'{v:.10f}')) for h, s, v in rows]
    return derive_expected(coordinates, rounded_rows)


def test_rust_program_and_results():
    # Retain and exercise all original fixed-fixture assertions.
    LOCATIONS.write_text(ORIGINAL_LOCATIONS)
    READINGS.write_text(ORIGINAL_READINGS)
    data = run_submission()
    assert_shape(data)
    profiles = data['most_similar_profiles']
    assert sorted(profiles) == ['S1', 'S2'], f"Expected most_similar_profiles to be ['S1', 'S2'], got {profiles}"
    assert math.isclose(data['profile_distance'], 0.7788, abs_tol=1e-4), f"Expected profile_distance to be ~0.7788, got {data['profile_distance']}"
    assert math.isclose(data['spatial_distance'], 5.0000, abs_tol=1e-4), f"Expected spatial_distance to be ~5.0000, got {data['spatial_distance']}"

    # Replace both inputs with an unpredictable fixture and independently derive its answer.
    expected_profiles, expected_profile_distance, expected_spatial_distance = write_random_fixture()
    data = run_submission()
    assert_shape(data)
    assert data['most_similar_profiles'] == expected_profiles, (
        f"Expected most_similar_profiles {expected_profiles}, got {data['most_similar_profiles']}"
    )
    assert math.isclose(data['profile_distance'], expected_profile_distance, abs_tol=5e-5), (
        f"Expected profile_distance {expected_profile_distance:.4f}, got {data['profile_distance']}"
    )
    assert math.isclose(data['spatial_distance'], expected_spatial_distance, abs_tol=5e-5), (
        f"Expected spatial_distance {expected_spatial_distance:.4f}, got {data['spatial_distance']}"
    )
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
