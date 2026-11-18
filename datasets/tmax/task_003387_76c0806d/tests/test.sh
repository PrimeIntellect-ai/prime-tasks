#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import subprocess
import tempfile
import uuid

import netCDF4 as nc
import numpy as np
import pytest

EXECUTABLE = "/home/user/filter"
SOURCE = "/home/user/filter.c"
THRESHOLD = 3.82


def signal_ratio(path):
    with nc.Dataset(path, "r") as ds:
        assert "signal" in ds.variables, f"Missing signal variable in {path}"
        values = np.asarray(ds.variables["signal"][:], dtype=np.float64).reshape(-1)
    assert values.size >= 2
    mean = math.fsum(values.tolist()) / values.size
    squared = math.fsum((float(x) - mean) ** 2 for x in values)
    stddev = math.sqrt(squared / (values.size - 1))
    assert stddev > 0.0
    return max(abs(float(x) - mean) for x in values) / stddev


def run_filter(path):
    try:
        return subprocess.run(
            [EXECUTABLE, path], capture_output=True, timeout=10
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Filter timed out on {path}")


def test_filter_artifacts_exist():
    assert os.path.isfile(SOURCE), f"Expected C source not found at {SOURCE}"
    assert os.path.isfile(EXECUTABLE), f"Expected executable not found at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as binary:
        assert binary.read(4) == b"\x7fELF", "Compiled filter must be an ELF executable"


def test_provided_corpus_using_specified_statistic():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith(".nc")]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith(".nc")]
    assert clean_files, "No clean files found."
    assert evil_files, "No evil files found."

    failures = []
    for path in clean_files + evil_files:
        ratio = signal_ratio(path)
        expected = 1 if ratio > THRESHOLD else 0
        actual = run_filter(path)
        if actual != expected:
            failures.append(
                f"{os.path.basename(path)}: ratio={ratio:.9f}, expected {expected}, got {actual}"
            )
    assert not failures, " | ".join(failures)


def make_signal(rng, size, target):
    base = np.clip(rng.normal(0.0, 1.0, size), -2.4, 2.4).astype(np.float64)
    index = int(rng.integers(0, size))
    base[index] = 0.0

    def ratio_for(value):
        data = base.copy()
        data[index] = value
        return np.max(np.abs(data - data.mean())) / data.std(ddof=1)

    low = 0.0
    high = 4.0
    while ratio_for(high) < target:
        high *= 2.0
    for _ in range(100):
        middle = (low + high) / 2.0
        if ratio_for(middle) < target:
            low = middle
        else:
            high = middle
    base[index] = (low + high) / 2.0

    scale = float(rng.uniform(0.3, 4.0))
    offset = float(rng.uniform(-20.0, 20.0))
    return (base * scale + offset).astype(np.float32)


def test_filter_on_unlabelled_generated_inputs():
    rng = np.random.default_rng(int.from_bytes(os.urandom(16), "big"))
    specifications = [
        (257, 2.8),
        (389, 3.55),
        (503, 3.79),
        (128, 3.81),
        (271, 3.83),
        (643, 3.90),
        (811, 4.4),
        (997, 6.0),
    ]

    with tempfile.TemporaryDirectory(prefix="nc_inputs_") as directory:
        cases = []
        for size, target in specifications:
            path = os.path.join(directory, uuid.uuid4().hex + ".nc")
            values = make_signal(rng, size, target)
            with nc.Dataset(path, "w", format="NETCDF4") as ds:
                ds.createDimension("time", size)
                signal = ds.createVariable("signal", "f4", ("time",))
                signal[:] = values
            ratio = signal_ratio(path)
            expected = 1 if ratio > THRESHOLD else 0
            cases.append((path, ratio, expected))

        assert any(expected == 0 for _, _, expected in cases)
        assert any(expected == 1 for _, _, expected in cases)
        random.SystemRandom().shuffle(cases)

        failures = []
        for path, ratio, expected in cases:
            actual = run_filter(path)
            if actual != expected:
                failures.append(
                    f"generated input {os.path.basename(path)}: ratio={ratio:.9f}, "
                    f"expected {expected}, got {actual}"
                )
        assert not failures, " | ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
