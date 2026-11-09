#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_task.py
import math
import os
import re
import secrets
import subprocess
import tempfile

DATA = "/home/user/data/embeddings.csv"
SOURCE = "/home/user/src/normalize.c"
PROGRAM = "/home/user/src/normalize"
TRAIN_OUT = "/home/user/out/train_scaled.csv"
TEST_OUT = "/home/user/out/test_scaled.csv"
COV_OUT = "/home/user/out/test_covariance.txt"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def expected_rows(rows):
    mins = [min(row[j] for row in rows[:8]) for j in range(2)]
    maxs = [max(row[j] for row in rows[:8]) for j in range(2)]
    require(all(maxs[j] != mins[j] for j in range(2)), "Training feature has zero range")
    return [
        [
            (row[0] - mins[0]) / (maxs[0] - mins[0]),
            (row[1] - mins[1]) / (maxs[1] - mins[1]),
            row[2],
        ]
        for row in rows
    ]


def write_dataset(rows):
    with open(DATA, "w", encoding="utf-8", newline="") as f:
        for x, y, label in rows:
            f.write(f"{x:.9f},{y:.9f},{label}\n")


def parse_output(path, expected_count):
    require(os.path.isfile(path), f"{path} does not exist")
    with open(path, "r", encoding="utf-8") as f:
        raw_lines = f.readlines()
    require(len(raw_lines) == expected_count,
            f"Expected {expected_count} rows in {path}, found {len(raw_lines)}")

    parsed = []
    for index, raw in enumerate(raw_lines):
        line = raw.rstrip("\n")
        require(line != "" and line.count(",") == 2,
                f"Row {index + 1} of {path} is not strictly three comma-separated fields")
        parts = line.split(",")
        require(all(part != "" and part.strip() == part for part in parts),
                f"Malformed field in row {index + 1} of {path}")
        try:
            x = float(parts[0])
            y = float(parts[1])
            label = int(parts[2])
        except ValueError as exc:
            raise AssertionError(f"Non-numeric field in row {index + 1} of {path}") from exc
        require(math.isfinite(x) and math.isfinite(y),
                f"Non-finite feature in row {index + 1} of {path}")
        parsed.append((x, y, label))
    return parsed


def check_outputs(rows, tolerance=2e-6):
    expected = expected_rows(rows)
    train = parse_output(TRAIN_OUT, 8)
    test = parse_output(TEST_OUT, 2)
    actual = train + test
    for i, (got, want) in enumerate(zip(actual, expected)):
        require(abs(got[0] - want[0]) <= tolerance,
                f"Feature 0 is incorrect in output row {i + 1}: got {got[0]}, expected {want[0]}")
        require(abs(got[1] - want[1]) <= tolerance,
                f"Feature 1 is incorrect in output row {i + 1}: got {got[1]}, expected {want[1]}")
        require(got[2] == want[2],
                f"Label is incorrect in output row {i + 1}: got {got[2]}, expected {want[2]}")
    return train, test


def run_and_check(program, rows):
    for path in (TRAIN_OUT, TEST_OUT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    result = subprocess.run([program], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=10)
    require(result.returncode == 0,
            f"{program} exited with {result.returncode}: {result.stderr}")
    check_outputs(rows)


def random_dataset():
    rng = secrets.SystemRandom()
    first = [v / 1000.0 for v in rng.sample(range(-50000, 50001), 8)]
    second = [v / 1000.0 for v in rng.sample(range(-50000, 50001), 8)]
    rows = [[first[i], second[i], rng.randrange(2)] for i in range(8)]
    # Both test rows are extrema, so using all ten rows for min/max is detectably wrong.
    rows.append([max(first) + rng.uniform(2.0, 20.0),
                 min(second) - rng.uniform(2.0, 20.0), rng.randrange(2)])
    rows.append([min(first) - rng.uniform(2.0, 20.0),
                 max(second) + rng.uniform(2.0, 20.0), rng.randrange(2)])
    return rows


require(os.path.isfile(PROGRAM), "Compiled executable /home/user/src/normalize does not exist.")
require(os.access(PROGRAM, os.X_OK), "/home/user/src/normalize is not executable.")
with open(PROGRAM, "rb") as f:
    require(f.read(4) == b"\x7fELF", "/home/user/src/normalize is not a compiled ELF executable.")
require(os.path.isfile(SOURCE), f"{SOURCE} missing.")
require(os.path.isfile(COV_OUT), f"{COV_OUT} does not exist.")

with open(DATA, "rb") as f:
    original_data = f.read()
with open(COV_OUT, "rb") as f:
    submitted_covariance = f.read()

original_rows = []
for line in original_data.decode("utf-8").splitlines():
    parts = line.split(",")
    require(len(parts) == 3, "Original embeddings dataset is malformed")
    original_rows.append([float(parts[0]), float(parts[1]), int(parts[2])])
require(len(original_rows) == 10, "Expected ten rows in embeddings.csv")

try:
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "normalize_from_source")
        compile_result = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=20)
        require(compile_result.returncode == 0,
                f"Modified normalize.c does not compile: {compile_result.stderr}")

        # Exercise both the submitted executable and a fresh build of the modified source
        # against unpredictable datasets, checking every output row and field.
        for executable in (PROGRAM, rebuilt):
            for _ in range(3):
                rows = random_dataset()
                write_dataset(rows)
                run_and_check(executable, rows)

    # Restore the supplied dataset and verify that the submitted executable regenerates
    # the requested final CSV files rather than relying on pre-fabricated output.
    with open(DATA, "wb") as f:
        f.write(original_data)
    with open(COV_OUT, "wb") as f:
        f.write(submitted_covariance)
    run_and_check(PROGRAM, original_rows)

    train = parse_output(TRAIN_OUT, 8)
    test = parse_output(TEST_OUT, 2)

    # Preserve the original verifier's concrete assertions.
    require(abs(train[0][0] - 0.0) < 1e-4,
            "First feature of first train row is incorrect.")
    require(abs(train[0][1] - 0.142857) < 1e-4,
            "Second feature of first train row is incorrect.")
    require(train[0][2] == 0, "Label of first train row is incorrect.")
    require(abs(test[0][0] - 1.142857) < 1e-4,
            "Data leak not fixed: first test feature 0 is incorrect.")
    require(abs(test[0][1] - 1.285714) < 1e-4,
            "Data leak not fixed: first test feature 1 is incorrect.")
    require(test[0][2] == 0, "Label of first test row is incorrect.")
    require(abs(test[1][0] - 1.285714) < 1e-4,
            "Data leak not fixed: second test feature 0 is incorrect.")
    require(abs(test[1][1] - 1.142857) < 1e-4,
            "Data leak not fixed: second test feature 1 is incorrect.")
    require(test[1][2] == 1, "Label of second test row is incorrect.")

    with open(COV_OUT, "r", encoding="utf-8") as f:
        covariance_text = f.read().strip()
    require(re.fullmatch(r"-?\d+\.\d{4}", covariance_text) is not None,
            "test_covariance.txt must contain one value rounded to exactly 4 decimal places.")
    mean_x = sum(row[0] for row in test) / len(test)
    mean_y = sum(row[1] for row in test) / len(test)
    covariance = sum((row[0] - mean_x) * (row[1] - mean_y) for row in test) / (len(test) - 1)
    expected_covariance = f"{covariance:.4f}"
    require(covariance_text == expected_covariance,
            f"Expected covariance '{expected_covariance}', but found '{covariance_text}'.")
    require(covariance_text == "-0.0102",
            f"Expected covariance to be '-0.0102', but found '{covariance_text}'.")
finally:
    with open(DATA, "wb") as f:
        f.write(original_data)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
