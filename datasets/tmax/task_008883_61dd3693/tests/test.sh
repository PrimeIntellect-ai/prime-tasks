#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

import pytest

SOURCE_PATH = "/home/user/nanopore_filter.c"
RAW_PATH = "/home/user/raw_signal.csv"
OUTPUT_PATH = "/home/user/filtered_signal.csv"
BINARY_PATH = "/tmp/nanopore_filter_verifier"


def parse_and_check_output(text, expected_values, label):
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    assert lines, f"{label} is empty."
    assert lines[0] == "Time,FilteredSignal", (
        f"Incorrect header in {label}. Expected 'Time,FilteredSignal', got '{lines[0]}'"
    )
    assert len(lines) - 1 == len(expected_values), (
        f"Expected {len(expected_values)} data rows in {label}, but found {len(lines) - 1}."
    )

    for i, (expected_t, expected_y) in enumerate(expected_values):
        row = lines[i + 1]
        parts = row.split(",")
        assert len(parts) == 2, f"Row {i + 1} in {label} is malformed: '{row}'"
        try:
            actual_t = float(parts[0])
            actual_y = float(parts[1])
        except ValueError:
            pytest.fail(f"Row {i + 1} in {label} contains non-numeric data: '{row}'")
        assert math.isfinite(actual_t) and math.isfinite(actual_y), (
            f"Row {i + 1} in {label} contains NaN or Inf: '{row}'"
        )
        assert math.isclose(actual_t, expected_t, abs_tol=1e-3), (
            f"Time mismatch at row {i + 1}: expected {expected_t}, got {actual_t}"
        )
        assert math.isclose(actual_y, expected_y, rel_tol=1e-7, abs_tol=2e-6), (
            f"Signal mismatch at row {i + 1} (t={actual_t}): "
            f"expected {expected_y:.6f}, got {actual_y:.6f}"
        )


def expected_for(signals):
    y = 0.0
    h = 0.05 / 10.0
    tau = 0.01
    values = []
    for i, x in enumerate(signals):
        t = i * 0.05
        if i == 0:
            y = x
        else:
            for _ in range(10):
                y = y + (h / tau) * (x - y)
        values.append((t, y))
    return values


def test_filtered_signal_exists_and_correct():
    assert os.path.isfile(OUTPUT_PATH), (
        f"Output file {OUTPUT_PATH} is missing. Did you redirect the output?"
    )

    with open(OUTPUT_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, f"File {OUTPUT_PATH} is empty."

    header = lines[0]
    assert header == "Time,FilteredSignal", (
        f"Incorrect header in {OUTPUT_PATH}. Expected 'Time,FilteredSignal', got '{header}'"
    )

    # Recompute the expected values for the supplied observational data.
    expected_values = []
    y = 0.0
    dt = 0.05
    tau = 0.01
    h = dt / 10.0
    times = [round(i * 0.05, 2) for i in range(21)]
    signals = [0.0 if t < 0.50 else 1.0 for t in times]

    for t, x in zip(times, signals):
        if t == 0.0:
            y = x
            expected_values.append((t, y))
            continue
        for _ in range(10):
            y = y + (h / tau) * (x - y)
        expected_values.append((t, y))

    assert len(lines) - 1 == len(expected_values), (
        f"Expected {len(expected_values)} data rows, but found {len(lines) - 1}."
    )

    for i, (expected_t, expected_y) in enumerate(expected_values):
        row = lines[i + 1]
        parts = row.split(",")
        assert len(parts) == 2, f"Row {i + 1} is malformed: '{row}'"
        try:
            actual_t = float(parts[0])
            actual_y = float(parts[1])
        except ValueError:
            pytest.fail(f"Row {i + 1} contains non-numeric data: '{row}'")
        assert math.isclose(actual_t, expected_t, abs_tol=1e-3), (
            f"Time mismatch at row {i + 1}: expected {expected_t}, got {actual_t}"
        )
        assert math.isclose(actual_y, expected_y, abs_tol=1e-3), (
            f"Signal mismatch at row {i + 1} (t={actual_t}): "
            f"expected {expected_y:.6f}, got {actual_y:.6f}"
        )


def test_modified_c_program_compiles_and_handles_unseen_signals():
    assert os.path.isfile(SOURCE_PATH), f"Required C source {SOURCE_PATH} is missing."

    build = subprocess.run(
        ["gcc", "-std=c11", "-O0", SOURCE_PATH, "-o", BINARY_PATH, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert build.returncode == 0, f"Modified C program does not compile:\n{build.stderr}"
    assert os.path.isfile(BINARY_PATH) and os.access(BINARY_PATH, os.X_OK), (
        "Compiling nanopore_filter.c did not produce an executable program."
    )
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled artifact is not an ELF executable."

    with open(RAW_PATH, "rb") as f:
        original_raw = f.read()

    try:
        # Values are selected only at verification time, preventing a solution that
        # merely hardcodes the supplied 21-row step signal.
        for trial in range(3):
            count = 7 + trial
            signals = []
            for i in range(count):
                value = (secrets.randbelow(400001) - 200000) / 100000.0
                if i and math.isclose(value, signals[-1], abs_tol=1e-12):
                    value += 0.137
                signals.append(float(f"{value:.8f}"))

            with open(RAW_PATH, "w", encoding="utf-8") as f:
                f.write("Time,Signal\n")
                for i, x in enumerate(signals):
                    f.write(f"{i * 0.05:.2f},{x:.8f}\n")

            run = subprocess.run(
                [BINARY_PATH],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert run.returncode == 0, (
                f"Compiled program failed on verification input (trial {trial}):\n{run.stderr}"
            )
            parse_and_check_output(
                run.stdout,
                expected_for(signals),
                f"compiled program output for trial {trial}",
            )
    finally:
        with open(RAW_PATH, "wb") as f:
            f.write(original_raw)
        try:
            os.remove(BINARY_PATH)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
