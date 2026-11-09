#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import subprocess
import tempfile

import numpy as np
import pytest

SCRIPT_PATH = "/home/user/evaluate_run.sh"


def run_classifier(path):
    return subprocess.run(
        ["bash", SCRIPT_PATH, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )


def test_evaluate_run_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script missing: {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"Path is not a file: {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script is not executable: {SCRIPT_PATH}"


def test_adversarial_corpus():
    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"

    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))
    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))

    assert len(evil_files) > 0, "No evil files found to test."
    assert len(clean_files) > 0, "No clean files found to test."

    evil_bypassed = []
    for path in evil_files:
        result = run_classifier(path)
        if result.returncode != 1:
            evil_bypassed.append(os.path.basename(path))

    clean_modified = []
    for path in clean_files:
        result = run_classifier(path)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(path))

    errors = []
    if evil_bypassed:
        errors.append(
            f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: "
            + ", ".join(evil_bypassed)
        )
    if clean_modified:
        errors.append(
            f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): "
            + ", ".join(clean_modified)
        )

    if errors:
        pytest.fail(" | ".join(errors))


def independently_measure(t, values):
    dt = float(np.median(np.diff(t)))
    centered = values - np.mean(values)
    spectrum = np.abs(np.fft.rfft(centered))
    frequencies = np.fft.rfftfreq(len(values), d=dt)
    spectrum[0] = 0.0
    dominant_frequency = float(frequencies[int(np.argmax(spectrum))])

    amplitude = np.abs(values)
    peak_mask = (amplitude[1:-1] >= amplitude[:-2]) & (amplitude[1:-1] > amplitude[2:])
    peak_indices = np.nonzero(peak_mask)[0] + 1
    peak_indices = peak_indices[amplitude[peak_indices] > np.max(amplitude) * 1e-10]
    assert len(peak_indices) >= 20, "Generated signal did not have enough envelope peaks"
    growth_rate = float(
        np.polyfit(t[peak_indices], np.log(amplitude[peak_indices]), 1)[0]
    )
    return dominant_frequency, growth_rate


def test_generated_unseen_signals():
    # Use unpredictable parameters and neutral names so corpus paths and filenames
    # cannot reveal the expected result.
    rng = random.Random(secrets.randbits(128))
    sample_rate = 400.0
    duration = 8.0
    t = np.arange(0.0, duration, 1.0 / sample_rate)

    parameter_ranges = [
        (8.0, 30.0, 0.010, 0.055),   # below both thresholds
        (58.0, 85.0, 0.010, 0.055),  # frequency above threshold
        (8.0, 30.0, 0.115, 0.170),   # growth above threshold
        (58.0, 85.0, 0.115, 0.170),  # both above threshold
    ]

    generated = []
    with tempfile.TemporaryDirectory(prefix="runs_") as directory:
        for ranges in parameter_ranges:
            for _ in range(3):
                f_low, f_high, k_low, k_high = ranges
                frequency = rng.uniform(f_low, f_high)
                growth = rng.uniform(k_low, k_high)
                phase = rng.uniform(0.0, 2.0 * np.pi)
                amplitude = 10.0 ** rng.uniform(-2.0, 2.0)
                values = amplitude * np.exp(growth * t) * np.sin(
                    2.0 * np.pi * frequency * t + phase
                )

                measured_frequency, measured_growth = independently_measure(t, values)
                assert abs(measured_frequency - 45.0) > 5.0
                assert abs(measured_growth - 0.08) > 0.015
                expected = 1 if (measured_frequency > 45.0 or measured_growth > 0.08) else 0

                name = secrets.token_hex(12) + ".csv"
                path = os.path.join(directory, name)
                np.savetxt(
                    path,
                    np.column_stack((t, values)),
                    delimiter=",",
                    header="time,value",
                    comments="",
                )
                generated.append((path, expected, measured_frequency, measured_growth))

        rng.shuffle(generated)
        failures = []
        for path, expected, measured_frequency, measured_growth in generated:
            result = run_classifier(path)
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(path)}: expected exit {expected}, got "
                    f"{result.returncode} (frequency={measured_frequency:.4f}, "
                    f"growth={measured_growth:.5f}, stderr={result.stderr.decode(errors='replace')!r})"
                )

        if failures:
            pytest.fail("Generated-signal classification failures: " + " | ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
