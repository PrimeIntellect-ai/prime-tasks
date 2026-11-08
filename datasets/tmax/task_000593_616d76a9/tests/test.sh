#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import shutil
import subprocess
import tempfile

import numpy as np
import pytest
from netCDF4 import Dataset


def test_filter_go_exists():
    assert os.path.isfile("/home/user/filter.go"), "/home/user/filter.go does not exist."


def test_clean_corpus():
    clean_files = glob.glob("/app/corpus/clean/*.nc")
    assert len(clean_files) > 0, "No clean files found in /app/corpus/clean/"

    failures = []
    for filepath in clean_files:
        result = subprocess.run(
            ["go", "run", "/home/user/filter.go", filepath],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            failures.append(os.path.basename(filepath))

    if failures:
        pytest.fail(f"{len(failures)} of {len(clean_files)} clean files modified/rejected incorrectly: {', '.join(failures)}")


def test_evil_corpus():
    evil_files = glob.glob("/app/corpus/evil/*.nc")
    assert len(evil_files) > 0, "No evil files found in /app/corpus/evil/"

    failures = []
    for filepath in evil_files:
        result = subprocess.run(
            ["go", "run", "/home/user/filter.go", filepath],
            capture_output=True,
            text=True
        )
        if result.returncode != 1:
            failures.append(os.path.basename(filepath))

    if failures:
        pytest.fail(f"{len(failures)} of {len(evil_files)} evil files bypassed/accepted incorrectly: {', '.join(failures)}")


def classify_from_arrays(t, x, v):
    dt = t[1] - t[0]
    energy = 0.5 * v * v + 0.5 * x * x
    derivative = (energy[2:] - energy[:-2]) / (2.0 * dt)
    return 1 if np.max(np.abs(derivative)) > 0.001 else 0


def test_runtime_generated_unlabelled_cases():
    rng = np.random.default_rng(int.from_bytes(secrets.token_bytes(16), "big"))
    case_dir = tempfile.mkdtemp(prefix=".nc-cases-")
    cases = []
    desired_labels = [0] * 6 + [1] * 6
    rng.shuffle(desired_labels)

    try:
        for desired in desired_labels:
            n = int(rng.integers(45, 130))
            dt = float(rng.uniform(0.025, 0.2))
            t = float(rng.uniform(-20.0, 20.0)) + np.arange(n, dtype=np.float64) * dt
            base = float(rng.uniform(0.4, 2.0))

            if desired == 0:
                slope = float(rng.uniform(-0.00075, 0.00075))
                energy = base + slope * (t - t[0])
            elif rng.random() < 0.5:
                slope = float(rng.choice([-1.0, 1.0]) * rng.uniform(0.0015, 0.008))
                energy = base + slope * (t - t[0])
            else:
                energy = np.full(n, base, dtype=np.float64)
                index = int(rng.integers(2, n - 2))
                energy[index] += float(rng.uniform(0.02, 0.15))

            # Encode the selected energy trace without exposing its label in the path.
            x = np.sqrt(2.0 * energy)
            v = np.zeros(n, dtype=np.float64)
            expected = classify_from_arrays(t, x, v)
            assert expected == desired, "generated test case did not have its intended class"

            filepath = os.path.join(case_dir, secrets.token_hex(16) + ".nc")
            with Dataset(filepath, "w") as ds:
                ds.createDimension("dim", n)
                ds.createVariable("t", "f8", ("dim",))[:] = t
                ds.createVariable("x", "f8", ("dim",))[:] = x
                ds.createVariable("v", "f8", ("dim",))[:] = v
            cases.append((filepath, expected))

        rng.shuffle(cases)
        failures = []
        for filepath, expected in cases:
            result = subprocess.run(
                ["go", "run", "/home/user/filter.go", filepath],
                capture_output=True,
                text=True,
                timeout=60
            )
            if result.returncode != expected:
                failures.append(f"{os.path.basename(filepath)} expected {expected}, got {result.returncode}")

        if failures:
            pytest.fail("Runtime-generated NetCDF cases were misclassified: " + "; ".join(failures))
    finally:
        shutil.rmtree(case_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
