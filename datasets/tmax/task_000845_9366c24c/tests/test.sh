#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
from pathlib import Path
import secrets
import subprocess

import numpy as np
import pytest

DATA_PATH = Path('/home/user/ui_latency.csv')
OUTPUT_PATH = Path('/home/user/analysis.json')


def run_script(script):
    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()
    result = subprocess.run(
        ['python3', str(script)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'{script} exited with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert OUTPUT_PATH.exists(), f'{script} did not create {OUTPUT_PATH}.'
    assert OUTPUT_PATH.is_file(), f'The path {OUTPUT_PATH} is not a file.'


def load_result():
    with open(OUTPUT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'The file {OUTPUT_PATH} does not contain valid JSON.')


def write_signal(freq_hz, intended_slope, amplitude, phase, n=6000):
    timestamps = np.arange(n, dtype=float)
    latencies = (
        73.0
        + intended_slope * timestamps
        + amplitude * np.sin(2 * np.pi * freq_hz * timestamps / 1000.0 + phase)
    )
    with open(DATA_PATH, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['timestamp_ms', 'latency_us'])
        writer.writerows(zip(timestamps.astype(int), latencies))

    # Derive the expected answers from the generated samples rather than trusting
    # the parameters used to construct them.
    fit = np.polyfit(timestamps, latencies, 1)
    detrended = latencies - np.polyval(fit, timestamps)
    spectrum = np.abs(np.fft.rfft(detrended))
    spectrum[0] = 0
    frequencies = np.fft.rfftfreq(n, d=0.001)
    expected_frequency = int(round(float(frequencies[np.argmax(spectrum)])))
    expected_slope = round(float(fit[0]), 4)
    return expected_frequency, expected_slope


def assert_generated_result(expected_frequency, expected_slope):
    data = load_result()
    assert 'dominant_freq_hz' in data, "The JSON is missing the 'dominant_freq_hz' key."
    assert 'drift_slope' in data, "The JSON is missing the 'drift_slope' key."
    dominant_freq = data['dominant_freq_hz']
    drift_slope = data['drift_slope']
    assert isinstance(dominant_freq, int), (
        f"Expected 'dominant_freq_hz' to be an integer, got {type(dominant_freq).__name__}."
    )
    assert isinstance(drift_slope, (int, float)), (
        f"Expected 'drift_slope' to be a float, got {type(drift_slope).__name__}."
    )
    assert math.isfinite(float(drift_slope)), 'The drift slope must be finite.'
    assert dominant_freq == expected_frequency, (
        f'Expected dominant frequency to be {expected_frequency} Hz, got {dominant_freq}.'
    )
    assert abs(float(drift_slope) - expected_slope) < 0.000051, (
        f'Expected drift slope rounded to {expected_slope:.4f}, got {drift_slope}.'
    )


def assert_original_result():
    file_path = '/home/user/analysis.json'

    assert os.path.exists(file_path), f'The output file {file_path} does not exist.'
    assert os.path.isfile(file_path), f'The path {file_path} is not a file.'

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'The file {file_path} does not contain valid JSON.')

    assert 'dominant_freq_hz' in data, "The JSON is missing the 'dominant_freq_hz' key."
    assert 'drift_slope' in data, "The JSON is missing the 'drift_slope' key."

    dominant_freq = data['dominant_freq_hz']
    drift_slope = data['drift_slope']

    assert isinstance(dominant_freq, int), f"Expected 'dominant_freq_hz' to be an integer, got {type(dominant_freq).__name__}."
    assert isinstance(drift_slope, (int, float)), f"Expected 'drift_slope' to be a float, got {type(drift_slope).__name__}."

    assert dominant_freq == 60, f'Expected dominant frequency to be 60 Hz, got {dominant_freq}.'

    expected_slope = 0.0125
    assert abs(drift_slope - expected_slope) < 0.0002, f'Expected drift slope to be approximately {expected_slope}, got {drift_slope}.'


def test_processing_script_and_analysis():
    assert DATA_PATH.exists() and DATA_PATH.is_file(), f'The input dataset {DATA_PATH} is missing.'
    original_csv = DATA_PATH.read_bytes()
    original_json = OUTPUT_PATH.read_bytes() if OUTPUT_PATH.exists() and OUTPUT_PATH.is_file() else None

    scripts = sorted(
        p for p in Path('/home/user').rglob('*.py')
        if p.is_file() and not p.is_symlink()
    )
    assert scripts, 'No Python processing script was found under /home/user.'

    rng = secrets.SystemRandom()
    frequencies = rng.sample(range(23, 138), 2)
    cases = [
        (frequencies[0], rng.uniform(0.0012, 0.0048), 28.0, rng.uniform(0.1, 2.8)),
        (frequencies[1], rng.uniform(-0.0045, -0.0011), 35.0, rng.uniform(0.1, 2.8)),
    ]

    passing_script = None
    errors = []
    try:
        for script in scripts:
            try:
                for case in cases:
                    expected_frequency, expected_slope = write_signal(*case)
                    run_script(script)
                    assert_generated_result(expected_frequency, expected_slope)

                DATA_PATH.write_bytes(original_csv)
                run_script(script)
                assert_original_result()
                passing_script = script
                break
            except Exception as exc:
                errors.append(f'{script}: {exc}')

        assert passing_script is not None, (
            'No submitted Python script correctly processed both the supplied dataset '
            'and independently generated signals.\n' + '\n'.join(errors)
        )
    finally:
        DATA_PATH.write_bytes(original_csv)
        if passing_script is not None:
            run_script(passing_script)
        elif original_json is not None:
            OUTPUT_PATH.write_bytes(original_json)

    assert_original_result()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
