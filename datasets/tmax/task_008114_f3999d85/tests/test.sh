#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import subprocess

import pytest

JOINED = "/home/user/data/joined.csv"
WEIGHTS = "/home/user/data/weights.txt"
SOURCE = "/home/user/filter.c"
BINARY = "/home/user/filter"
FILTERED = "/home/user/filtered.csv"
BENCHMARK = "/home/user/benchmark.txt"


def canonical_data():
    random.seed(42)
    features = {}
    labels = {}
    for i in range(1, 101):
        x1_raw = random.uniform(0, 10)
        x2_raw = random.uniform(0, 10)
        features[i] = (round(x1_raw, 3), round(x2_raw, 3))
        y_true = 1.5 - 2.0 * x1_raw + 0.5 * x2_raw
        if i % 7 == 0:
            noise = random.uniform(3.0, 5.0) * random.choice([-1, 1])
        else:
            noise = random.uniform(-0.5, 0.5)
        labels[i] = round(y_true + noise, 3)
    return features, labels


def read_joined(path=JOINED):
    with open(path, newline="") as f:
        rows = [row for row in csv.reader(f) if row]
    for i, row in enumerate(rows):
        assert len(row) == 4, f"Line {i + 1} in {path} does not have 4 columns: {row}"
        try:
            ident = int(row[0])
            x1, x2, y = map(float, row[1:])
        except ValueError as exc:
            pytest.fail(f"Invalid numeric data on line {i + 1} of {path}: {exc}")
        assert all(math.isfinite(v) for v in (x1, x2, y))
        yield ident, x1, x2, y


def expected_valid(rows, weights):
    result = []
    for ident, x1, x2, y in rows:
        prediction = weights[0] + weights[1] * x1 + weights[2] * x2
        if (y - prediction) ** 2 < 2.0:
            result.append((ident, x1, x2, y, prediction))
    return result


def assert_filtered(expected):
    assert os.path.exists(FILTERED), f"Missing file: {FILTERED}"
    with open(FILTERED, newline="") as f:
        rows = [row for row in csv.reader(f) if row]
    assert len(rows) == len(expected), f"Expected {len(expected)} lines in {FILTERED}, got {len(rows)}"
    for line_no, (actual, wanted) in enumerate(zip(rows, expected), 1):
        assert len(actual) == 5, f"Line {line_no} in {FILTERED} does not have 5 columns: {actual}"
        assert re.fullmatch(r"-?\d+\.\d{3}", actual[4]), \
            f"Prediction on line {line_no} is not formatted to exactly 3 decimals: {actual[4]}"
        try:
            ident = int(actual[0])
            values = tuple(map(float, actual[1:]))
        except ValueError as exc:
            pytest.fail(f"Invalid filtered row {line_no}: {exc}")
        assert ident == wanted[0], f"Wrong ID on filtered line {line_no}"
        assert values[0] == pytest.approx(wanted[1], abs=1e-12)
        assert values[1] == pytest.approx(wanted[2], abs=1e-12)
        assert values[2] == pytest.approx(wanted[3], abs=1e-12)
        assert values[3] == pytest.approx(wanted[4], abs=0.0005001), \
            f"Wrong prediction on filtered line {line_no}: {values[3]} vs {wanted[4]}"


def run_binary():
    for path in (FILTERED, BENCHMARK):
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run([BINARY], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"filter failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
    assert os.path.exists(FILTERED), "Execution did not create filtered.csv"
    assert os.path.exists(BENCHMARK), "Execution did not create benchmark.txt"


def test_joined_csv():
    """Verify joined.csv is the complete, correct ID join."""
    assert os.path.exists(JOINED), f"Missing file: {JOINED}"
    rows = list(read_joined())
    assert len(rows) == 100, f"Expected 100 lines in {JOINED}, got {len(rows)}"

    features, labels = canonical_data()
    seen = set()
    for ident, x1, x2, y in rows:
        assert ident in features, f"Unexpected ID {ident} in joined.csv"
        assert ident not in seen, f"Duplicate ID {ident} in joined.csv"
        seen.add(ident)
        assert x1 == pytest.approx(features[ident][0], abs=1e-12)
        assert x2 == pytest.approx(features[ident][1], abs=1e-12)
        assert y == pytest.approx(labels[ident], abs=1e-12)
    assert seen == set(range(1, 101))

    with open(WEIGHTS) as f:
        weights = [float(line.strip()) for line in f if line.strip()]
    assert weights == pytest.approx([1.5, -2.0, 0.5], abs=1e-12)


def test_filter_c_code():
    """Verify filter.c exists and references the required BLAS and timing APIs."""
    assert os.path.exists(SOURCE), f"Missing file: {SOURCE}"
    with open(SOURCE) as f:
        content = f.read()
    assert "cblas.h" in content, f"cblas.h not included in {SOURCE}"
    assert re.search(r"\bcblas_ddot\s*\(", content), "filter.c does not call cblas_ddot"
    assert re.search(r"\bclock\s*\(", content), "filter.c does not call clock()"
    assert "10000" in content, "filter.c does not contain the required 10,000-iteration benchmark"


def test_build_execute_and_dynamic_behavior():
    """Build submitted source, exercise it on derived inputs, then regenerate final outputs."""
    result = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", BINARY, "-lopenblas"],
        capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"Compilation failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.exists(BINARY), f"Missing binary: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"File is not executable: {BINARY}"

    linked = subprocess.run(["ldd", BINARY], capture_output=True, text=True)
    assert linked.returncode == 0, f"ldd failed on {BINARY}"
    assert "openblas" in linked.stdout.lower(), f"Binary {BINARY} is not linked to OpenBLAS"

    with open(JOINED, "rb") as f:
        original_joined = f.read()
    with open(WEIGHTS, "rb") as f:
        original_weights = f.read()

    challenge = [
        (901, 1.25, -0.5, -1.8125),
        (177, -2.0, 3.0, 10.25),
        (808, 0.0, 0.0, 2.75),
        (333, 4.0, 1.5, -3.5),
        (444, -1.0, -2.0, -3.4),
        (555, 2.0, 2.0, 0.83),
    ]
    challenge_weights = [0.75, -1.25, 2.0]

    try:
        with open(JOINED, "w", newline="") as f:
            csv.writer(f).writerows(challenge)
        with open(WEIGHTS, "w") as f:
            f.write("0.75\n-1.25\n2.0\n")
        run_binary()
        assert_filtered(expected_valid(challenge, challenge_weights))
    finally:
        with open(JOINED, "wb") as f:
            f.write(original_joined)
        with open(WEIGHTS, "wb") as f:
            f.write(original_weights)

    run_binary()


def test_filtered_csv():
    """Verify every selected row, threshold decision, value, and prediction format."""
    rows = list(read_joined())
    expected = expected_valid(rows, [1.5, -2.0, 0.5])
    assert len(expected) == 86, f"Expected canonical dataset to have 86 valid rows, got {len(expected)}"
    assert_filtered(expected)


def test_benchmark_txt():
    """Verify execution produced a finite positive benchmark value."""
    assert os.path.exists(BENCHMARK), f"Missing file: {BENCHMARK}"
    with open(BENCHMARK) as f:
        content = f.read().strip()
    assert re.fullmatch(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", content), \
        f"benchmark.txt must contain only one floating-point number: {content!r}"
    time_val = float(content)
    assert math.isfinite(time_val), f"Benchmark must be finite, got {time_val}"
    assert time_val > 0.0, f"Benchmark time must be > 0, got {time_val}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
