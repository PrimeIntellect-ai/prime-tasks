#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import secrets
import subprocess
import tempfile

import cv2
import numpy as np
import pytest


def test_video_telemetry_extraction():
    csv_path = '/home/user/video_telemetry.csv'
    video_path = '/app/machine_monitor.mp4'
    assert os.path.isfile(csv_path), f"Telemetry CSV file {csv_path} is missing."

    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ['frame_index', 'brightness'], f"CSV header is incorrect. Expected ['frame_index', 'brightness'], got {header}."

        rows = list(reader)
        assert len(rows) == 100, f"Expected 100 rows of telemetry data, got {len(rows)}."

        submitted = []
        for i, row in enumerate(rows):
            assert len(row) == 2, f"Row {i} has incorrect number of columns."
            frame_index = int(row[0])
            brightness = float(row[1])

            assert frame_index == i, f"Expected frame_index {i}, got {frame_index}."

            expected_brightness = 100 + 50 * math.sin(i * 0.1)
            assert abs(brightness - expected_brightness) <= 1.0, f"Row {i}: Expected brightness ~{expected_brightness:.2f}, got {brightness}."
            submitted.append(brightness)

    # Derive the authoritative values by decoding the supplied video rather than
    # trusting the known formula used to create it.
    cap = cv2.VideoCapture(video_path)
    assert cap.isOpened(), f"Could not open source video {video_path}."
    decoded = []
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        decoded.append(round(float(gray.mean()), 2))
    cap.release()

    assert len(decoded) == len(rows), f"Source video has {len(decoded)} frames but telemetry has {len(rows)} rows."
    for i, (actual, expected) in enumerate(zip(submitted, decoded)):
        assert abs(actual - expected) <= 0.0051, f"Row {i}: decoded video brightness is {expected:.2f}, got {actual}."


def run_classifier(classifier_path, fpath):
    result = subprocess.run(
        ['python3', classifier_path, fpath],
        capture_output=True,
        text=True,
        timeout=20,
    )
    return result.stdout.strip()


def test_adversarial_classifier():
    classifier_path = '/home/user/classifier.py'
    assert os.path.isfile(classifier_path), f"Classifier script {classifier_path} is missing."

    clean_dir = '/app/corpus/test/clean'
    evil_dir = '/app/corpus/test/evil'

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.csv')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.csv')]

    assert len(clean_files) > 0, "No clean test files found."
    assert len(evil_files) > 0, "No evil test files found."

    clean_failures = []
    for fpath in clean_files:
        output = run_classifier(classifier_path, fpath)
        if output != 'CLEAN':
            clean_failures.append((os.path.basename(fpath), output))

    evil_failures = []
    for fpath in evil_files:
        output = run_classifier(classifier_path, fpath)
        if output != 'EVIL':
            evil_failures.append((os.path.basename(fpath), output))

    error_msg = ""
    if clean_failures:
        error_msg += f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected. Offending files: {[f[0] for f in clean_failures]}.\n"
    if evil_failures:
        error_msg += f"{len(evil_failures)} of {len(evil_files)} evil bypassed. Offending files: {[f[0] for f in evil_failures]}.\n"

    assert not clean_failures and not evil_failures, error_msg.strip()

    # Generate fresh clean and evil logs after the agent has finished. All files
    # share one neutral directory and opaque names, so labels cannot be inferred
    # from paths. Expected labels are retained only in verifier memory.
    rng = np.random.default_rng(secrets.randbits(128))
    cases = [('CLEAN', 3.5, 10.0, 2.0)] * 8
    cases += [('EVIL', 3.8, 10.0, 2.0)] * 4
    cases += [('EVIL', 3.5, 16.0, 2.0)] * 4
    cases += [('EVIL', 3.5, 10.0, 8.0)] * 4
    rng.shuffle(cases)

    generated_failures = []
    with tempfile.TemporaryDirectory(prefix='evaluation_') as tmpdir:
        generated = []
        for expected, slope, intercept, noise_sd in cases:
            name = secrets.token_hex(16) + '.csv'
            path = os.path.join(tmpdir, name)
            temperature = rng.uniform(20.0, 80.0, 500)
            pressure = slope * temperature + intercept + rng.normal(0.0, noise_sd, 500)
            with open(path, 'w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['temperature', 'pressure'])
                for t, p in zip(temperature, pressure):
                    writer.writerow([f'{t:.4f}', f'{p:.4f}'])
            generated.append((path, expected))

        rng.shuffle(generated)
        for path, expected in generated:
            output = run_classifier(classifier_path, path)
            if output != expected:
                generated_failures.append((os.path.basename(path), expected, output))

    assert not generated_failures, (
        f"Classifier failed {len(generated_failures)} fresh neutral-path cases: "
        f"{generated_failures}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
