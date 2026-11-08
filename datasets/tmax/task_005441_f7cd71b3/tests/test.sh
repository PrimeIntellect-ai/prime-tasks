#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import secrets
import shutil
import subprocess
import tempfile

import pytest


def test_valid_samples_log():
    log_path = "/home/user/valid_samples.log"
    assert os.path.isfile(log_path), f"Output log file is missing: {log_path}"

    with open(log_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_data = {
        "sample_1.csv": 0.016641,
        "sample_10.csv": 0.025409,
        "sample_3.csv": 0.014238,
        "sample_4.csv": 0.028911,
        "sample_6.csv": 0.012586,
        "sample_7.csv": 0.029462,
        "sample_9.csv": 0.008906
    }

    expected_files = sorted(expected_data.keys())
    actual_files = []

    for line in lines:
        parts = line.split(',')
        assert len(parts) == 2, f"Invalid line format in log: '{line}'"
        filename, val_str = parts[0], parts[1]

        assert filename in expected_data, f"Unexpected file in log (or KL div should have been >= 0.15): {filename}"

        try:
            val = float(val_str)
        except ValueError:
            pytest.fail(f"Could not parse KL divergence as float: {val_str}")

        assert math.isfinite(val), f"KL divergence must be finite: {val_str}"
        expected_val = expected_data[filename]
        assert abs(val - expected_val) < 0.001, f"KL divergence for {filename} is {val}, expected ~{expected_val}"

        actual_files.append(filename)

    assert actual_files == expected_files, f"Log file is not sorted alphabetically or missing files. Expected {expected_files}, got {actual_files}"


def _distribution(path):
    points = []
    with open(path, "r") as f:
        for line in f:
            x_text, y_text = line.strip().split(',')
            points.append((float(x_text), float(y_text)))

    assert len(points) == 100
    x0, y0 = points[0]
    xn, yn = points[-1]
    slope = (yn - y0) / (xn - x0)
    corrected = []
    for x, y in points:
        baseline = y0 + slope * (x - x0)
        corrected.append(max(y - baseline, 1e-6))
    total = sum(corrected)
    return [value / total for value in corrected]


def _kl(sample_path, reference_path):
    p = _distribution(sample_path)
    q = _distribution(reference_path)
    return sum(pv * math.log(pv / qv) for pv, qv in zip(p, q))


def test_processor_compiles_and_processes_fresh_inputs():
    source = "/home/user/processor.c"
    assert os.path.isfile(source), f"Required C source is missing: {source}"

    executable = os.path.join(tempfile.mkdtemp(prefix="processor-build-"), "processor")
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", source, "-lm", "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"processor.c did not compile:\n{compile_result.stderr}"

    raw_path = "/home/user/spectra_raw"
    reference_path = "/home/user/reference_spectrum.csv"
    log_path = "/home/user/valid_samples.log"
    backup_root = tempfile.mkdtemp(prefix="spectra-backup-")
    backup_raw = os.path.join(backup_root, "spectra_raw")
    backup_reference = os.path.join(backup_root, "reference_spectrum.csv")
    backup_log = os.path.join(backup_root, "valid_samples.log")

    os.replace(raw_path, backup_raw)
    os.replace(reference_path, backup_reference)
    if os.path.exists(log_path):
        os.replace(log_path, backup_log)

    try:
        os.mkdir(raw_path)
        rng = random.Random(secrets.randbits(128))
        xs = [400.0 + 400.0 * i / 99.0 for i in range(100)]

        def gaussian(mu, sigma):
            values = [math.exp(-((x - mu) ** 2) / (2.0 * sigma ** 2)) for x in xs]
            values[0] = 0.0
            values[-1] = 0.0
            return values

        def write_spectrum(path, signal):
            intercept = rng.uniform(0.4, 2.2)
            slope = rng.uniform(-0.003, 0.003)
            scale = rng.uniform(0.7, 1.8)
            with open(path, "w") as f:
                for x, value in zip(xs, signal):
                    y = intercept + slope * (x - 400.0) + scale * value
                    f.write(f"{x:.9f},{y:.9f}\n")

        reference_signal = gaussian(600.0, 28.0)
        write_spectrum(reference_path, reference_signal)

        profiles = [
            reference_signal,
            gaussian(607.0, 30.0),
            gaussian(593.0, 25.0),
            gaussian(680.0, 25.0),
            gaussian(510.0, 30.0),
            [a + 1.3 * b for a, b in zip(reference_signal, gaussian(500.0, 22.0))],
        ]
        identifiers = rng.sample(range(100, 9999), len(profiles))
        rng.shuffle(profiles)

        all_files = []
        for identifier, profile in zip(identifiers, profiles):
            filename = f"sample_{identifier}.csv"
            write_spectrum(os.path.join(raw_path, filename), profile)
            all_files.append(filename)

        expected = {}
        for filename in all_files:
            divergence = _kl(os.path.join(raw_path, filename), reference_path)
            assert math.isfinite(divergence)
            if divergence < 0.15:
                expected[filename] = divergence

        assert expected, "Internal test fixture produced no valid samples"
        assert len(expected) < len(all_files), "Internal test fixture produced no rejected samples"

        run_result = subprocess.run(
            [executable],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert run_result.returncode == 0, f"Compiled processor failed:\n{run_result.stderr}"
        assert os.path.isfile(log_path), "Compiled processor did not create valid_samples.log"

        with open(log_path, "r") as f:
            lines = [line.rstrip("\n") for line in f if line.strip()]

        expected_names = sorted(expected)
        actual_names = []
        for line in lines:
            match = re.fullmatch(r"([^,]+\.csv),(0\.\d{6})", line)
            assert match is not None, f"Invalid output format: {line!r}"
            filename, value_text = match.groups()
            assert filename in expected, f"Unexpected or invalid sample in fresh output: {filename}"
            value = float(value_text)
            assert math.isfinite(value)
            assert abs(value - expected[filename]) <= 2e-6, (
                f"Wrong KL divergence for {filename}: got {value_text}, expected {expected[filename]:.6f}"
            )
            actual_names.append(filename)

        assert actual_names == expected_names, (
            f"Fresh output is unsorted, missing samples, or has duplicates. "
            f"Expected {expected_names}, got {actual_names}"
        )
    finally:
        shutil.rmtree(raw_path, ignore_errors=True)
        if os.path.exists(reference_path):
            os.remove(reference_path)
        if os.path.exists(log_path):
            os.remove(log_path)
        os.replace(backup_raw, raw_path)
        os.replace(backup_reference, reference_path)
        if os.path.exists(backup_log):
            os.replace(backup_log, log_path)
        shutil.rmtree(backup_root, ignore_errors=True)
        shutil.rmtree(os.path.dirname(executable), ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
