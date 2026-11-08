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

PIPELINE = "/home/user/pipeline"
DATA = "/home/user/data.csv"
OUTPUT = "/home/user/test_transformed.csv"
SOURCE = "/home/user/pipeline/src/main.rs"


def expected_rows(records):
    train = records[:800]
    n = len(train)
    mean_f1 = sum(r[0] for r in train) / n
    mean_f2 = sum(r[1] for r in train) / n
    std_f1 = math.sqrt(sum((r[0] - mean_f1) ** 2 for r in train) / (n - 1))
    std_f2 = math.sqrt(sum((r[1] - mean_f2) ** 2 for r in train) / (n - 1))

    rows = []
    for f1, f2, label in records[800:]:
        reduced_f = (((f1 - mean_f1) / std_f1) + ((f2 - mean_f2) / std_f2)) / 2.0
        rows.append([f"{reduced_f:.4f}", str(label)])
    return rows


def assert_output_matches(records):
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} is missing after running the pipeline."
    with open(OUTPUT, newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        actual = list(reader)

    assert header == ["reduced_f", "label"], f"Expected header ['reduced_f', 'label'], got {header}"
    expected = expected_rows(records)
    assert len(actual) == 200, f"Expected exactly 200 rows in the test set, got {len(actual)}"
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert got == want, f"Row {i + 1} mismatch: expected {want}, got {got}"


def run_pipeline():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PIPELINE,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"Rust pipeline failed to compile or run (exit {result.returncode}).\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert re.search(r"inference\s*(?:time|timing)|(?:time|timing).*inference", result.stdout, re.I), (
        f"Pipeline stdout did not report inference timing. stdout was: {result.stdout!r}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_and_exercise_rust_pipeline():
    assert os.path.isfile(SOURCE), f"Rust source file {SOURCE} is missing."
    assert os.path.isfile(os.path.join(PIPELINE, "Cargo.toml")), "Cargo.toml is missing."

    with open(DATA, "rb") as f:
        original_data = f.read()

    rng = random.SystemRandom()
    probe = []
    for i in range(1000):
        # Independent, non-linear values prevent a fixed output or whole-dataset
        # statistics from satisfying this verification run.
        f1 = float(rng.randrange(-500000, 500001) + i * i)
        f2 = float(rng.randrange(-700000, 700001) - 3 * i * i + 17 * i)
        probe.append((f1, f2, rng.randrange(0, 2)))

    try:
        with open(DATA, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["f1", "f2", "label"])
            writer.writerows(probe)
        run_pipeline()
        assert_output_matches(probe)
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)

    # Run once more on the task's real dataset so the final artifact is produced
    # by the submitted Rust program and remains available for the original checks.
    try:
        run_pipeline()
    finally:
        with open(DATA, "wb") as f:
            f.write(original_data)


def test_test_transformed_exists():
    """Check that the output file exists."""
    assert os.path.exists("/home/user/test_transformed.csv"), "Output file /home/user/test_transformed.csv is missing."


def test_test_transformed_content():
    """Verify the contents of the transformed test set."""
    # Recompute train statistics
    train_f1 = [float(i) for i in range(1, 801)]
    train_f2 = [float(i * 2) for i in range(1, 801)]

    n_train = len(train_f1)
    mean_f1 = sum(train_f1) / n_train
    mean_f2 = sum(train_f2) / n_train

    var_f1 = sum((x - mean_f1)**2 for x in train_f1) / (n_train - 1)
    var_f2 = sum((x - mean_f2)**2 for x in train_f2) / (n_train - 1)

    std_f1 = math.sqrt(var_f1)
    std_f2 = math.sqrt(var_f2)

    # Generate expected test rows
    expected_rows_fixed = []
    for i in range(801, 1001):
        f1 = float(i)
        f2 = float(i * 2)
        label = i % 2

        f1_scaled = (f1 - mean_f1) / std_f1
        f2_scaled = (f2 - mean_f2) / std_f2
        reduced_f = (f1_scaled + f2_scaled) / 2.0

        expected_rows_fixed.append([f"{reduced_f:.4f}", str(label)])

    # Read actual test rows
    actual_rows = []
    with open("/home/user/test_transformed.csv", "r") as f:
        reader = csv.reader(f)
        header = next(reader)
        assert header == ["reduced_f", "label"], f"Expected header ['reduced_f', 'label'], got {header}"

        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) == 200, f"Expected exactly 200 rows in the test set, got {len(actual_rows)}"

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows_fixed)):
        assert actual == expected, f"Row {i + 1} mismatch: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
