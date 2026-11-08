#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import struct
import subprocess

import pytest

PROJECT_DIR = "/home/user/math_prep"
DATASET_PATH = "/home/user/dataset.txt"
CSV_PATH = "/home/user/experiment_log.csv"
EXPECTED_MSE = None


def f32(value):
    return struct.unpack("!f", struct.pack("!f", value))[0]


def evaluate(parts, cast, rounded_ops=False):
    a = cast(float(parts[0]))
    b = cast(float(parts[2]))
    c = cast(float(parts[4]))
    op1, op2 = parts[1], parts[3]

    def apply(x, op, y):
        result = x + y if op == "+" else x * y
        return cast(result) if rounded_ops else result

    if op1 == "+" and op2 == "*":
        return apply(a, "+", apply(b, "*", c))
    return apply(apply(a, op1, b), op2, c)


def compute_expected(lines):
    squared_error = 0.0
    for line in lines:
        parts = line.split()
        assert len(parts) == 5
        result32 = evaluate(parts, f32, rounded_ops=True)
        result64 = evaluate(parts, float, rounded_ops=False)
        difference = float(result32) - result64
        squared_error += difference * difference
    return squared_error / len(lines)


def make_dataset():
    rng = random.SystemRandom()
    while True:
        lines = []
        for _ in range(10000):
            values = [rng.randint(-100_000_000, 100_000_000) / 1_000_000 for _ in range(3)]
            op1 = rng.choice(("+", "*"))
            op2 = rng.choice(("+", "*"))
            lines.append(f"{values[0]:.6f} {op1} {values[1]:.6f} {op2} {values[2]:.6f}")
        expected = compute_expected(lines)
        if 0.0 < expected < 100.0 and f"{expected:.6f}" != "0.000000":
            return lines, expected


@pytest.fixture(scope="session", autouse=True)
def build_and_run_application():
    global EXPECTED_MSE

    cargo_toml = os.path.join(PROJECT_DIR, "Cargo.toml")
    main_rs = os.path.join(PROJECT_DIR, "src", "main.rs")
    assert os.path.isfile(cargo_toml), "Rust project 'math_prep' not found at /home/user/math_prep. Cargo.toml is missing."
    assert os.path.isfile(main_rs), "Rust application source is missing at /home/user/math_prep/src/main.rs."

    with open(DATASET_PATH, "rb") as f:
        original_dataset = f.read()

    lines, EXPECTED_MSE = make_dataset()
    try:
        with open(DATASET_PATH, "w", newline="\n") as f:
            f.write("\n".join(lines) + "\n")

        if os.path.exists(CSV_PATH):
            os.remove(CSV_PATH)

        result = subprocess.run(
            ["cargo", "run", "--release", "--quiet", "--manifest-path", cargo_toml],
            cwd=PROJECT_DIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
        )
        assert result.returncode == 0, (
            "Rust application failed to compile or run.\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )
        yield
    finally:
        with open(DATASET_PATH, "wb") as f:
            f.write(original_dataset)


def test_rust_project_exists():
    """Test that the Rust project was created in the correct directory."""
    cargo_toml_path = "/home/user/math_prep/Cargo.toml"
    assert os.path.isfile(cargo_toml_path), "Rust project 'math_prep' not found at /home/user/math_prep. Cargo.toml is missing."


def test_experiment_log_exists():
    """Test that the experiment_log.csv file was generated."""
    assert os.path.isfile(CSV_PATH), "experiment_log.csv not found at /home/user/experiment_log.csv."


def test_experiment_log_content():
    """Test the structure and values in experiment_log.csv."""
    with open(CSV_PATH, "r", newline="") as f:
        rows = list(csv.reader(f))

    assert len(rows) == 2, f"Expected exactly 2 rows (header + 1 data row) in CSV, found {len(rows)}."

    header = rows[0]
    expected_header = ["num_samples", "mse", "duration_ms"]
    assert header == expected_header, f"Incorrect CSV header. Expected {expected_header}, got {header}."

    data = rows[1]
    assert len(data) == 3, f"Expected 3 columns in data row, got {len(data)}."
    num_samples, mse_str, duration_str = data

    assert num_samples == "10000", f"Expected num_samples to be '10000', got '{num_samples}'."

    try:
        mse = float(mse_str)
    except ValueError:
        pytest.fail(f"MSE value '{mse_str}' is not a valid float.")

    assert math.isfinite(mse), f"MSE value {mse_str} must be finite."
    assert 0.0 < mse < 100.0, f"MSE value {mse} is out of expected bounds (0.0 < mse < 100.0)."
    assert re.fullmatch(r"[0-9]+\.[0-9]{6}", mse_str), f"MSE value '{mse_str}' is not formatted to exactly 6 decimal places."
    expected_mse_str = f"{EXPECTED_MSE:.6f}"
    assert mse_str == expected_mse_str, f"Incorrect MSE. Expected {expected_mse_str}, got {mse_str}."

    try:
        duration = int(duration_str)
    except ValueError:
        pytest.fail(f"Duration value '{duration_str}' is not a valid integer.")

    assert duration >= 0, f"Duration {duration} must be a non-negative integer."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
