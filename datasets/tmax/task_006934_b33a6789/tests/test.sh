#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import glob
import pytest

RAW_DATA_DIR = "/home/user/raw_data"
OUTPUT_CSV = "/home/user/training_data.csv"
RUST_PROJECT_DIR = "/home/user/spectro_prep"

def compute_expected_output():
    files = glob.glob(os.path.join(RAW_DATA_DIR, "*.csv"))
    res = []
    for f in files:
        wavelengths = []
        intensities = []
        with open(f, 'r') as csvfile:
            reader = csv.DictReader(csvfile)
            for row in reader:
                wavelengths.append(float(row['wavelength']))
                intensities.append(float(row['intensity']))

        n = len(intensities)
        smoothed = [0.0] * n
        for i in range(2, n - 2):
            smoothed[i] = sum(intensities[i-2:i+3]) / 5.0

        peaks = []
        for i in range(1, n - 1):
            if smoothed[i] > smoothed[i-1] and smoothed[i] > smoothed[i+1]:
                peaks.append((smoothed[i], wavelengths[i]))

        peaks.sort(reverse=True, key=lambda x: x[0])

        p1 = peaks[0][1] if len(peaks) > 0 else 0.0
        p2 = peaks[1][1] if len(peaks) > 1 else 0.0
        p3 = peaks[2][1] if len(peaks) > 2 else 0.0

        res.append({
            'filename': os.path.basename(f),
            'peak1_wl': f"{p1:.1f}",
            'peak2_wl': f"{p2:.1f}",
            'peak3_wl': f"{p3:.1f}"
        })

    res.sort(key=lambda x: x['filename'])
    return res

def test_rust_project_exists():
    assert os.path.isdir(RUST_PROJECT_DIR), f"Rust project directory {RUST_PROJECT_DIR} is missing."
    cargo_toml = os.path.join(RUST_PROJECT_DIR, "Cargo.toml")
    assert os.path.isfile(cargo_toml), f"Cargo.toml is missing in {RUST_PROJECT_DIR}."

def test_output_csv_exists():
    assert os.path.isfile(OUTPUT_CSV), f"Output file {OUTPUT_CSV} is missing."

def test_output_csv_contents():
    expected_data = compute_expected_output()

    assert os.path.isfile(OUTPUT_CSV), f"Output file {OUTPUT_CSV} is missing."

    actual_data = []
    with open(OUTPUT_CSV, 'r') as csvfile:
        reader = csv.DictReader(csvfile)
        assert reader.fieldnames == ['filename', 'peak1_wl', 'peak2_wl', 'peak3_wl'], \
            f"Incorrect header in {OUTPUT_CSV}. Expected 'filename,peak1_wl,peak2_wl,peak3_wl'."
        for row in reader:
            actual_data.append(row)

    assert len(actual_data) == len(expected_data), \
        f"Expected {len(expected_data)} rows in {OUTPUT_CSV}, but found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual['filename'] == expected['filename'], \
            f"Row {i+1}: expected filename {expected['filename']}, got {actual['filename']}"
        assert actual['peak1_wl'] == expected['peak1_wl'], \
            f"Row {i+1} ({expected['filename']}): expected peak1_wl {expected['peak1_wl']}, got {actual['peak1_wl']}"
        assert actual['peak2_wl'] == expected['peak2_wl'], \
            f"Row {i+1} ({expected['filename']}): expected peak2_wl {expected['peak2_wl']}, got {actual['peak2_wl']}"
        assert actual['peak3_wl'] == expected['peak3_wl'], \
            f"Row {i+1} ({expected['filename']}): expected peak3_wl {expected['peak3_wl']}, got {actual['peak3_wl']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
