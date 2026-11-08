#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import stat
import struct
import subprocess

import pytest

SOURCE = "/home/user/process_data.cpp"
DATASET = "/home/user/dataset.bin"
PREDICTIONS = "/home/user/test_predictions.txt"
EXECUTABLE = "/tmp/process_data_verified"
NUM_SAMPLES = 12000
TRAIN_SIZE = 10000
NUM_FEATURES = 5
WEIGHTS = [0.5, -0.2, 0.1, 0.8, -0.5]
BIAS = 0.1
LINE_FORMAT = re.compile(r"^-?\d+\.\d{4}$")


def read_dataset(path):
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "rb") as f:
        raw = f.read()

    expected_bytes = NUM_SAMPLES * NUM_FEATURES * 4
    assert len(raw) == expected_bytes, (
        f"Expected {NUM_SAMPLES} samples in dataset.bin, got "
        f"{len(raw) // (NUM_FEATURES * 4)}"
    )

    values = [item[0] for item in struct.iter_unpack("f", raw)]
    return [values[i:i + NUM_FEATURES] for i in range(0, len(values), NUM_FEATURES)]


def expected_predictions(data):
    assert len(data) == NUM_SAMPLES, (
        f"Expected {NUM_SAMPLES} samples in dataset.bin, got {len(data)}"
    )

    means = [0.0] * NUM_FEATURES
    for i in range(TRAIN_SIZE):
        for j in range(NUM_FEATURES):
            means[j] += data[i][j]
    for j in range(NUM_FEATURES):
        means[j] /= TRAIN_SIZE

    stddevs = [0.0] * NUM_FEATURES
    for i in range(TRAIN_SIZE):
        for j in range(NUM_FEATURES):
            stddevs[j] += (data[i][j] - means[j]) ** 2
    for j in range(NUM_FEATURES):
        stddevs[j] = math.sqrt(stddevs[j] / TRAIN_SIZE)
        assert stddevs[j] > 0

    expected = []
    for i in range(TRAIN_SIZE, NUM_SAMPLES):
        pred = BIAS
        for j in range(NUM_FEATURES):
            pred += ((data[i][j] - means[j]) / stddevs[j]) * WEIGHTS[j]
        expected.append(pred)
    return expected


def run_and_check():
    data = read_dataset(DATASET)
    expected = expected_predictions(data)

    if os.path.lexists(PREDICTIONS):
        os.remove(PREDICTIONS)

    subprocess.run([EXECUTABLE], cwd="/home/user", check=True, timeout=30)
    assert os.path.isfile(PREDICTIONS), (
        f"File {PREDICTIONS} is missing. Did you compile and run the program?"
    )

    with open(PREDICTIONS, "r", encoding="utf-8") as f:
        actual_lines = f.read().splitlines()

    assert len(actual_lines) == 2000, (
        f"Expected exactly 2000 predictions in {PREDICTIONS}, but got "
        f"{len(actual_lines)}. Ensure you only output predictions for the test set."
    )

    for idx, (expected_value, actual) in enumerate(zip(expected, actual_lines)):
        assert LINE_FORMAT.fullmatch(actual), (
            f"Line {idx + 1} in {PREDICTIONS} must be formatted with exactly "
            f"4 decimal places: {actual!r}"
        )
        try:
            actual_value = float(actual)
        except ValueError:
            pytest.fail(f"Line {idx + 1} in {PREDICTIONS} is not a valid float: {actual}")
        assert abs(expected_value - actual_value) < 1e-3, (
            f"Mismatch at test sample {idx + 1}: expected {expected_value:.4f}, "
            f"got {actual_value:.4f}. Check your normalizer or loop bounds."
        )


def write_fresh_dataset(path):
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    train_offsets = [rng.uniform(-4.0, 4.0) for _ in range(NUM_FEATURES)]
    train_scales = [rng.uniform(0.5, 3.0) for _ in range(NUM_FEATURES)]
    test_shifts = [rng.uniform(2.0, 6.0) * (-1 if rng.randrange(2) else 1)
                   for _ in range(NUM_FEATURES)]

    with open(path, "wb") as f:
        for i in range(NUM_SAMPLES):
            for j in range(NUM_FEATURES):
                value = train_offsets[j] + train_scales[j] * rng.uniform(-2.0, 2.0)
                if i >= TRAIN_SIZE:
                    value += test_shifts[j]
                f.write(struct.pack("f", value))


def test_fixed_cpp_program():
    assert os.path.lexists(SOURCE), f"File {SOURCE} is missing."
    mode = os.lstat(SOURCE).st_mode
    assert stat.S_ISREG(mode), f"File {SOURCE} must be a regular C++ source file."

    subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", EXECUTABLE],
        check=True,
        timeout=60,
    )
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK)

    with open(DATASET, "rb") as f:
        original_dataset = f.read()

    try:
        # Preserve the original behavioral check on the supplied dataset.
        run_and_check()

        # Exercise the compiled C++ artifact on unseen data so a precomputed
        # predictions file or hardcoded answers cannot pass.
        write_fresh_dataset(DATASET)
        run_and_check()
    finally:
        with open(DATASET, "wb") as f:
            f.write(original_dataset)

    # Leave the requested output corresponding to the supplied dataset.
    run_and_check()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
