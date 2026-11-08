#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import secrets
import subprocess
import tempfile

import pytest

PROJECT_DIR = "/home/user/sensor_project"
DATA_FILE = os.path.join(PROJECT_DIR, "sensor_data.txt")
OUTPUT_FILE = os.path.join(PROJECT_DIR, "processed_output.csv")
PROCESSOR_FILE = os.path.join(PROJECT_DIR, "processor.c")


def compute_expected_values(data):
    expected = [["Line", "Value", "MovingAvg", "RunningVar"]]
    window = []
    mean = 0.0
    m2 = 0.0

    for i, val in enumerate(data):
        count = i + 1
        delta = val - mean
        mean += delta / count
        delta2 = val - mean
        m2 += delta * delta2
        variance = m2 / (count - 1) if count > 1 else 0.0

        window.append(val)
        if len(window) > 5:
            window.pop(0)
        moving_average = sum(window) / len(window)

        expected.append([
            str(count),
            f"{val:.2f}",
            f"{moving_average:.2f}",
            f"{variance:.6f}",
        ])

    return expected


def compute_expected_output(data_file):
    if not os.path.exists(data_file):
        return []
    with open(data_file, "r") as f:
        data = [float(line.strip()) for line in f if line.strip()]
    return compute_expected_values(data)


def parse_csv(text):
    return list(csv.reader(io.StringIO(text)))


def assert_rows_equal(actual_rows, expected_rows):
    assert len(actual_rows) == len(expected_rows), (
        f"Row count mismatch. Expected {len(expected_rows)} rows, "
        f"found {len(actual_rows)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, (
            f"Mismatch at row {i + 1}.\nExpected: {expected}\nFound:    {actual}"
        )


@pytest.fixture(scope="session")
def compiled_processor():
    assert os.path.isfile(PROCESSOR_FILE), f"The C processor file is missing: {PROCESSOR_FILE}"
    build_dir = tempfile.mkdtemp(prefix="processor-build-")
    executable = os.path.join(build_dir, "processor")
    result = subprocess.run(
        ["gcc", "-O2", "-std=c11", PROCESSOR_FILE, "-o", executable, "-lm"],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, f"processor.c did not compile:\n{result.stderr}"
    assert os.path.isfile(executable) and os.access(executable, os.X_OK)
    return executable


def run_processor(executable, values):
    with tempfile.NamedTemporaryFile(mode="w", delete=False, prefix="sensor-input-", suffix=".txt") as f:
        for value in values:
            f.write(f"{value:.12f}\n")
        input_path = f.name

    try:
        result = subprocess.run(
            [executable, input_path],
            cwd=PROJECT_DIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
    finally:
        os.unlink(input_path)

    assert result.returncode == 0, (
        f"The compiled processor failed with exit code {result.returncode}.\n"
        f"stderr:\n{result.stderr}"
    )
    return parse_csv(result.stdout)


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"The output file was not found at {OUTPUT_FILE}."


def test_output_content_is_correct():
    assert os.path.isfile(DATA_FILE), f"The input data file is missing: {DATA_FILE}"
    expected_rows = compute_expected_output(DATA_FILE)
    assert expected_rows, "Expected output could not be computed (input data might be empty)."

    assert os.path.isfile(OUTPUT_FILE), f"The output file is missing: {OUTPUT_FILE}"
    with open(OUTPUT_FILE, "r") as f:
        actual_rows = list(csv.reader(f))

    assert_rows_equal(actual_rows, expected_rows)


def test_processor_reproduces_saved_output(compiled_processor):
    with open(DATA_FILE, "r") as f:
        values = [float(line.strip()) for line in f if line.strip()]
    actual_rows = run_processor(compiled_processor, values)
    expected_rows = compute_expected_values(values)
    assert_rows_equal(actual_rows, expected_rows)

    with open(OUTPUT_FILE, "r") as f:
        saved_rows = list(csv.reader(f))
    assert actual_rows == saved_rows, "processed_output.csv was not produced by the corrected processor behavior."


def test_processor_code_changes(compiled_processor):
    assert os.path.isfile(PROCESSOR_FILE), f"The C processor file is missing: {PROCESSOR_FILE}"

    # Inputs are generated only at verification time. Their large common offset makes
    # the naive sum-of-squares variance numerically unstable, while lengths above five
    # exercise every moving-window boundary.
    rng = secrets.SystemRandom()
    baseline = float(rng.randrange(100_000_000, 900_000_000))
    offsets = [
        0.11, -0.07, 0.19, -0.13, 0.05, 0.23, -0.17, 0.09,
        -0.21, 0.15, 0.03, -0.09, 0.27, -0.15, 0.07, 0.17,
    ]
    rng.shuffle(offsets)
    values = [baseline + offset for offset in offsets]

    actual_rows = run_processor(compiled_processor, values)
    expected_rows = compute_expected_values(values)
    assert_rows_equal(actual_rows, expected_rows)

    second_values = [
        41.13, 41.27, 40.91, 41.44, 40.72, 41.36,
        40.84, 41.58, 40.69, 41.21, 41.03,
    ]
    assert_rows_equal(
        run_processor(compiled_processor, second_values),
        compute_expected_values(second_values),
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
