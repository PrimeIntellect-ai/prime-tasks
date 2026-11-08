#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import subprocess
import tempfile

import netCDF4 as nc
import numpy as np
import pytest


def test_detector_exists_and_executable():
    detector_path = "/home/user/detector"
    assert os.path.exists(detector_path), f"Missing detector executable at {detector_path}"
    assert os.path.isfile(detector_path), f"{detector_path} is not a file"
    assert os.access(detector_path, os.X_OK), f"{detector_path} is not executable"


def test_detector_adversarial_corpus():
    detector_path = "/home/user/detector"
    evil_dir = "/app/test_corpus/evil"
    clean_dir = "/app/test_corpus/clean"

    evil_files = glob.glob(os.path.join(evil_dir, "*.nc"))
    clean_files = glob.glob(os.path.join(clean_dir, "*.nc"))

    assert len(evil_files) > 0, f"No evil files found in {evil_dir}"
    assert len(clean_files) > 0, f"No clean files found in {clean_dir}"

    evil_bypassed = []
    for f in evil_files:
        try:
            result = subprocess.run([detector_path, f], capture_output=True, text=True, timeout=2)
            output = result.stdout.strip()
            if output != "REJECT":
                evil_bypassed.append(os.path.basename(f))
        except Exception as e:
            evil_bypassed.append(os.path.basename(f) + f" (Error: {e})")

    clean_rejected = []
    for f in clean_files:
        try:
            result = subprocess.run([detector_path, f], capture_output=True, text=True, timeout=2)
            output = result.stdout.strip()
            if output != "ACCEPT":
                clean_rejected.append(os.path.basename(f))
        except Exception as e:
            clean_rejected.append(os.path.basename(f) + f" (Error: {e})")

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        error_messages.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_rejected)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def test_detector_on_fresh_label_neutral_inputs():
    detector_path = "/home/user/detector"
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))

    labels = [False] * 24 + [True] * 24
    rng.shuffle(labels)

    with tempfile.TemporaryDirectory(prefix="detector_holdout_") as corpus_dir:
        cases = []
        for anomalous in labels:
            t = np.linspace(0.0, 10.0, 1000)
            phase = rng.uniform(-np.pi, np.pi)
            frequency = rng.uniform(0.8, 1.2)
            noise_sigma = rng.uniform(0.006, 0.014)
            data = np.sin(frequency * t + phase) + rng.normal(0.0, noise_sigma, 1000)

            if anomalous:
                positions = rng.choice(np.arange(50, 950), size=2, replace=False)
                data[positions[0]] += rng.uniform(25.0, 40.0)
                data[positions[1]] -= rng.uniform(25.0, 40.0)

            second_difference_sum = float(np.abs(data[2:] - 2.0 * data[1:-1] + data[:-2]).sum())
            expected = "REJECT" if second_difference_sum > 50.0 else "ACCEPT"
            assert (expected == "REJECT") == anomalous

            path = os.path.join(corpus_dir, secrets.token_hex(16) + ".nc")
            with nc.Dataset(path, "w", format="NETCDF4") as dataset:
                dataset.createDimension("time", 1000)
                signal = dataset.createVariable("signal", "f8", ("time",))
                signal[:] = data
            cases.append((path, expected))

        rng.shuffle(cases)
        failures = []
        for path, expected in cases:
            try:
                result = subprocess.run(
                    [detector_path, path], capture_output=True, text=True, timeout=2
                )
                actual = result.stdout.strip()
                if actual != expected:
                    failures.append(f"{os.path.basename(path)}: expected {expected}, got {actual!r}")
            except Exception as e:
                failures.append(f"{os.path.basename(path)}: {e}")

        if failures:
            pytest.fail(f"Fresh randomized corpus failures ({len(failures)}): " + " | ".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
