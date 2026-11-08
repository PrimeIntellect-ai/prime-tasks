#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
from pathlib import Path

SCRIPT_PATH = Path("/home/user/run_pipeline.sh")
RAW_PATH = Path("/home/user/raw_data.csv")
CLEANED_PATH = Path("/home/user/cleaned_data.csv")
CORRELATION_PATH = Path("/home/user/correlation.txt")


def _run_pipeline():
    subprocess.run(
        [str(SCRIPT_PATH)],
        cwd="/home/user",
        check=True,
        timeout=30,
    )


def _remove_outputs():
    CLEANED_PATH.unlink(missing_ok=True)
    CORRELATION_PATH.unlink(missing_ok=True)


def _pearson(xs, ys):
    mean_x = sum(xs) / len(xs)
    mean_y = sum(ys) / len(ys)
    numerator = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    denominator = math.sqrt(
        sum((x - mean_x) ** 2 for x in xs)
        * sum((y - mean_y) ** 2 for y in ys)
    )
    return numerator / denominator


def _assert_generated_outputs(expected_rows):
    assert CLEANED_PATH.is_file(), f"Cleaned data file not found: {CLEANED_PATH}"
    assert CORRELATION_PATH.is_file(), f"Correlation file not found: {CORRELATION_PATH}"

    lines = [line.strip() for line in CLEANED_PATH.read_text().splitlines() if line.strip()]
    assert len(lines) == len(expected_rows), (
        f"Expected {len(expected_rows)} rows in cleaned data, found {len(lines)}"
    )

    ratios = []
    targets = []
    for index, (line, expected) in enumerate(zip(lines, expected_rows), 1):
        parts = line.split(",")
        assert len(parts) == 5, f"Row {index} does not have exactly 5 columns: {line}"
        try:
            parsed = (int(parts[0]),) + tuple(float(value) for value in parts[1:])
        except ValueError:
            assert False, f"Row {index} contains invalid numerical values: {line}"

        assert parsed[0] == expected[0], f"Row {index} ID mismatch"
        for column in range(1, 5):
            assert math.isclose(parsed[column], expected[column], rel_tol=1e-9, abs_tol=1e-9), (
                f"Row {index} column {column + 1} mismatch: "
                f"expected {expected[column]}, got {parsed[column]}"
            )
        ratios.append(expected[3])
        targets.append(expected[4])

    content = CORRELATION_PATH.read_text().strip()
    assert re.fullmatch(r"-?\d+\.\d{4}", content), (
        "Correlation output must contain one number rounded to exactly 4 decimal places"
    )
    expected_correlation = f"{_pearson(ratios, targets):.4f}"
    assert content == expected_correlation, (
        f"Correlation value incorrect: expected '{expected_correlation}', got '{content}'"
    )


def test_pipeline_script_executable_and_reproducible():
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script_path), f"Pipeline script not found: {script_path}"
    assert os.access(script_path, os.X_OK), f"Pipeline script is not executable: {script_path}"

    original_raw = RAW_PATH.read_bytes()
    rng = secrets.SystemRandom()
    nonce = rng.randrange(100000, 900000)
    ratios = rng.sample([n for n in range(-15, 16) if n not in (0,)], 8)
    denominators = [2, -3, 4, 5, -2, 3, 6, -4]

    raw_rows = []
    expected_rows = []
    for i, (ratio, denominator) in enumerate(zip(ratios, denominators)):
        if i == 2:
            raw_rows.append((nonce + 80, "17.0", "0", "123.0"))
        if i == 6:
            raw_rows.append((nonce + 81, "-9.0", "0.0", "-77.0"))

        row_id = nonce + i
        sensor_x = ratio * denominator
        target = ratio * 2.75 + rng.randrange(-30, 31) / 10.0
        raw_rows.append((row_id, f"{sensor_x}.0", f"{denominator}.0", f"{target:.3f}"))
        expected_rows.append(
            (row_id, float(sensor_x), float(denominator), float(sensor_x) / denominator, float(f"{target:.3f}"))
        )

    dynamic_raw = "id,sensor_x,sensor_y,target_val\n" + "\n".join(
        ",".join(map(str, row)) for row in raw_rows
    ) + "\n"

    try:
        RAW_PATH.write_text(dynamic_raw)
        _remove_outputs()
        _run_pipeline()
        _assert_generated_outputs(expected_rows)
        first_cleaned = CLEANED_PATH.read_bytes()
        first_correlation = CORRELATION_PATH.read_bytes()

        RAW_PATH.write_text(dynamic_raw)
        _remove_outputs()
        _run_pipeline()
        _assert_generated_outputs(expected_rows)
        assert CLEANED_PATH.read_bytes() == first_cleaned, "Cleaned output is not reproducible"
        assert CORRELATION_PATH.read_bytes() == first_correlation, "Correlation output is not reproducible"
    finally:
        RAW_PATH.write_bytes(original_raw)
        _remove_outputs()
        _run_pipeline()


def test_cleaned_data_content():
    cleaned_data_path = "/home/user/cleaned_data.csv"
    assert os.path.isfile(cleaned_data_path), f"Cleaned data file not found: {cleaned_data_path}"

    expected_rows = [
        (1, 10.0, 2.0, 5.0, 15.0),
        (3, 15.0, 3.0, 5.0, 20.0),
        (4, 20.0, 4.0, 5.0, 25.0),
        (5, -5.0, 1.0, -5.0, -10.0),
        (6, 12.0, 2.0, 6.0, 18.0),
        (7, 9.0, -3.0, -3.0, -8.0),
        (8, 0.0, 5.0, 0.0, 2.0),
        (10, -10.0, -2.0, 5.0, 12.0)
    ]

    with open(cleaned_data_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_rows), f"Expected {len(expected_rows)} rows in cleaned data, found {len(lines)}"

    for i, (line, expected) in enumerate(zip(lines, expected_rows)):
        parts = line.split(",")
        assert len(parts) == 5, f"Row {i+1} does not have exactly 5 columns: {line}"

        try:
            parsed_row = (
                int(parts[0]),
                float(parts[1]),
                float(parts[2]),
                float(parts[3]),
                float(parts[4])
            )
        except ValueError:
            assert False, f"Row {i+1} contains invalid numerical values: {line}"

        assert parsed_row[0] == expected[0], f"Row {i+1} ID mismatch: expected {expected[0]}, got {parsed_row[0]}"
        for j in range(1, 5):
            assert math.isclose(parsed_row[j], expected[j], rel_tol=1e-4, abs_tol=1e-4), \
                f"Row {i+1} column {j+1} mismatch: expected {expected[j]}, got {parsed_row[j]}"


def test_correlation_output():
    correlation_path = "/home/user/correlation.txt"
    assert os.path.isfile(correlation_path), f"Correlation file not found: {correlation_path}"

    with open(correlation_path, "r") as f:
        content = f.read().strip()

    assert content == "0.9404", f"Correlation value incorrect: expected '0.9404', got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
