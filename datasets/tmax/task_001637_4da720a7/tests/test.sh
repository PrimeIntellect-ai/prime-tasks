#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import json
import os
import random
import secrets
import subprocess
import tempfile

import cv2
import numpy as np
import pytest


def reference_data():
    timestamps = []
    speeds = []
    steering = []
    missing = []
    with open('/app/telemetry_base.csv', newline='') as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader):
            timestamps.append(float(row['timestamp']))
            steering.append(float(row['steering']))
            value = row['speed'].strip()
            if value == '' or value.lower() in ('nan', 'null', 'none'):
                speeds.append(float('nan'))
                missing.append(i)
            else:
                speeds.append(float(value))

    timestamps = np.asarray(timestamps, dtype=float)
    speeds = np.asarray(speeds, dtype=float)
    valid = np.isfinite(speeds)
    interpolated = np.interp(timestamps, timestamps[valid], speeds[valid])

    cap = cv2.VideoCapture('/app/dashcam.mp4')
    brightness = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        brightness.append(float(np.mean(gray)))
    cap.release()
    assert brightness, 'Reference video could not be decoded'
    return timestamps, interpolated, np.asarray(steering), brightness, len(missing)


def test_rust_implementation_artifacts():
    detector = '/home/user/detector'
    assert os.path.isfile(detector), f'Detector binary not found at {detector}'
    assert os.access(detector, os.X_OK), f'Detector binary at {detector} is not executable'
    with open(detector, 'rb') as f:
        binary = f.read()
    assert binary.startswith(b'\x7fELF'), 'Detector must be a compiled native binary, not a script'
    rust_markers = (b'/rustc/', b'rust_begin_unwind', b'rust_eh_personality', b'core::panicking')
    assert any(marker in binary for marker in rust_markers), 'Detector does not appear to be compiled from Rust'

    sources = glob.glob('/home/user/**/*.rs', recursive=True)
    assert sources, 'No Rust source files were found under /home/user'
    source_text = ''
    for path in sources:
        try:
            with open(path, encoding='utf-8', errors='ignore') as f:
                source_text += '\n' + f.read().lower()
        except OSError:
            pass
    for required in ('raw_sensor', 'sensor_scaled', 'brightness', 'speed', 'steering'):
        assert required in source_text, f'Rust sources do not contain the required {required} processing logic'


def test_video_joined_csv():
    joined_path = '/home/user/video_joined.csv'
    assert os.path.exists(joined_path), f'File not found: {joined_path}'

    with open(joined_path, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['timestamp', 'speed', 'steering', 'brightness'], \
            f'Unexpected joined schema: {reader.fieldnames}'
        rows = list(reader)

    assert len(rows) == 50, f'Expected 50 rows in {joined_path}, found {len(rows)}'

    # Preserve the original fixed assertion.
    row_25 = next((r for r in rows if abs(float(r['timestamp']) - 2.5) < 0.01), None)
    assert row_25 is not None, 'Row with timestamp 2.5 not found'
    brightness_25 = float(row_25['brightness'])
    assert abs(brightness_25 - 245.0) < 5.0, \
        f'Expected brightness near 245.0 at timestamp 2.5, got {brightness_25}'
    assert row_25['speed'] != '', 'Speed at timestamp 2.5 should not be empty'
    assert row_25['speed'].lower() != 'nan', 'Speed at timestamp 2.5 should not be NaN'

    telemetry_ts, expected_speed, expected_steering, expected_brightness, _ = reference_data()
    assert len(expected_brightness) == len(rows)

    seen = set()
    for frame_index, row in enumerate(rows):
        assert set(row) == {'timestamp', 'speed', 'steering', 'brightness'}
        try:
            actual = {key: float(row[key]) for key in row}
        except (TypeError, ValueError) as exc:
            pytest.fail(f'Row {frame_index} is not strictly numeric: {exc}')
        assert all(np.isfinite(v) for v in actual.values()), f'Row {frame_index} contains a non-finite value'

        frame_ts = frame_index / 10.0
        nearest = int(np.argmin(np.abs(telemetry_ts - frame_ts)))
        assert abs(actual['timestamp'] - float(telemetry_ts[nearest])) < 1e-8, \
            f'Incorrect timestamp at frame {frame_index}'
        assert actual['timestamp'] not in seen, f'Duplicate timestamp {actual["timestamp"]}'
        seen.add(actual['timestamp'])
        assert abs(actual['speed'] - float(expected_speed[nearest])) < 1e-6, \
            f'Incorrect/interpolated speed at frame {frame_index}'
        assert abs(actual['steering'] - float(expected_steering[nearest])) < 1e-6, \
            f'Incorrect steering at frame {frame_index}'
        assert abs(actual['brightness'] - expected_brightness[frame_index]) < 3.0, \
            f'Incorrect brightness at frame {frame_index}'


def test_experiment_log():
    log_path = '/home/user/experiment_log.json'
    assert os.path.exists(log_path), f'File not found: {log_path}'
    with open(log_path) as f:
        try:
            log_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {log_path} is not valid JSON')

    # Preserve the original assertions.
    assert log_data.get('video_frames_processed') == 50, 'Expected video_frames_processed to be 50'
    assert abs(log_data.get('max_brightness', 0) - 245.0) < 5.0, 'Expected max_brightness near 245.0'
    assert log_data.get('missing_speeds_imputed') == 2, 'Expected missing_speeds_imputed to be 2'

    _, _, _, brightness, missing_count = reference_data()
    assert type(log_data.get('video_frames_processed')) is int
    assert type(log_data.get('missing_speeds_imputed')) is int
    assert isinstance(log_data.get('max_brightness'), (int, float))
    assert log_data['video_frames_processed'] == len(brightness)
    assert abs(float(log_data['max_brightness']) - max(brightness)) < 3.0
    assert log_data['missing_speeds_imputed'] == missing_count


def run_detector(path):
    return subprocess.run(['/home/user/detector', path], capture_output=True, timeout=10).returncode


def write_generated_case(path, evil, rng):
    n = int(rng.integers(65, 180))
    mean = float(rng.uniform(-250.0, 400.0))
    std = float(rng.uniform(0.5, 80.0))
    raw = rng.normal(mean, std, n)
    if evil:
        scaled = (raw - np.mean(raw)) / np.std(raw)
    else:
        scaled = np.zeros(n, dtype=float)
        for j in range(2, n):
            past = raw[:j]
            scaled[j] = (raw[j] - np.mean(past)) / (np.std(past) + 1e-5)
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['raw_sensor', 'sensor_scaled'])
        writer.writerows(zip(raw, scaled))


def test_adversarial_detector():
    detector_path = '/home/user/detector'
    assert os.path.exists(detector_path), f'Detector binary not found at {detector_path}'
    assert os.access(detector_path, os.X_OK), f'Detector binary at {detector_path} is not executable'

    clean_files = glob.glob('/app/hidden_corpus/clean/*.csv')
    evil_files = glob.glob('/app/hidden_corpus/evil/*.csv')
    assert len(clean_files) > 0, 'No clean corpus files found'
    assert len(evil_files) > 0, 'No evil corpus files found'

    clean_failures = [os.path.basename(p) for p in clean_files if run_detector(p) != 0]
    evil_failures = [os.path.basename(p) for p in evil_files if run_detector(p) != 1]
    errors = []
    if clean_failures:
        errors.append(f'{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {", ".join(clean_failures)}')
    if evil_failures:
        errors.append(f'{len(evil_failures)} of {len(evil_files)} evil bypassed: {", ".join(evil_failures)}')
    if errors:
        pytest.fail(' | '.join(errors))

    # Generate fresh cases and repeatedly use the same neutrally named path, so
    # neither directory names nor filenames reveal the expected classification.
    rng = np.random.default_rng(secrets.randbits(128))
    cases = [False] * 12 + [True] * 12
    random.SystemRandom().shuffle(cases)
    with tempfile.TemporaryDirectory(prefix='vendor_batch_') as tmp:
        neutral_path = os.path.join(tmp, 'sample.csv')
        for index, evil in enumerate(cases):
            write_generated_case(neutral_path, evil, rng)
            expected = 1 if evil else 0
            actual = run_detector(neutral_path)
            assert actual == expected, \
                f'Detector returned {actual} for generated case {index}; expected {expected}'
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
