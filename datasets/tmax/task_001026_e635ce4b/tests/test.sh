#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import os
import random
import re
import shutil
import subprocess

HOME = "/home/user"
SOURCE = os.path.join(HOME, "train.c")
DATASET = os.path.join(HOME, "dataset.csv")
OUTPUT = os.path.join(HOME, "model_output.txt")
BINARY = "/tmp/train_verifier"


def solve_ols(rows):
    # Solve (X^T X)b = X^T y for X = [1, sensor_count, temperature].
    a = [[0.0] * 4 for _ in range(3)]
    for sensor, temp, target in rows:
        x = [1.0, float(sensor), float(temp)]
        for i in range(3):
            for j in range(3):
                a[i][j] += x[i] * x[j]
            a[i][3] += x[i] * target

    for col in range(3):
        pivot = max(range(col, 3), key=lambda r: abs(a[r][col]))
        assert abs(a[pivot][col]) > 1e-10, "Generated regression matrix is singular"
        a[col], a[pivot] = a[pivot], a[col]
        divisor = a[col][col]
        for j in range(col, 4):
            a[col][j] /= divisor
        for row in range(3):
            if row == col:
                continue
            factor = a[row][col]
            for j in range(col, 4):
                a[row][j] -= factor * a[col][j]
    return [a[i][3] for i in range(3)]


def read_exact_output():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist after running train.c"
    with open(OUTPUT, "r", encoding="utf-8") as f:
        content = f.read()

    lines = content.splitlines()
    assert len(lines) == 3, "model_output.txt must contain exactly three lines"
    patterns = [
        r"Intercept: (-?\d+\.\d{4})",
        r"Coefficient sensor_count: (-?\d+\.\d{4})",
        r"Coefficient temperature_celsius: (-?\d+\.\d{4})",
    ]
    values = []
    for line, pattern in zip(lines, patterns):
        match = re.fullmatch(pattern, line)
        assert match, f"Incorrect output line or formatting: {line!r}"
        values.append(match.group(1))
    return values


def run_and_check(expected):
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [BINARY], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"Compiled train.c exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    actual = read_exact_output()
    assert actual == expected, f"Expected coefficients {expected}, got {actual}"


def make_random_dataset(rng):
    valid = []
    lines = ["sensor_count,temperature_celsius,failure_rate"]
    for i in range(18):
        sensor = 2 + i
        temp = round(rng.uniform(12.0, 34.0) + (i % 4) * 0.17, 6)
        target = round(1.7 + 0.18 * sensor - 0.07 * temp + rng.uniform(-0.35, 0.35), 6)
        valid.append((sensor, temp, target))
        lines.append(f"{sensor},{temp:.6f},{target:.6f}")

    # Every one of these rows violates the required three-column numeric schema.
    # Large target values ensure that accepting malformed rows changes the model.
    invalid = [
        ",22.0,9999", "9,,9999", "9,22.0,", "NaN,22.0,9999",
        "9,NaN,9999", "9,22.0,NaN", "N/A,22.0,9999",
        "4.5,22.0,9999", "10x,22.0,9999", "10,22C,9999",
        "10,22.0,not-a-number"
    ]
    rng.shuffle(invalid)
    for row in invalid:
        lines.insert(rng.randrange(1, len(lines) + 1), row)
    return "\n".join(lines) + "\n", valid


def main():
    # Preserve the original verifier's existence and installed-header assertions.
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} does not exist."
    assert (os.path.exists("/usr/include/gsl/gsl_fit.h") or
            os.path.exists("/usr/include/gsl/gsl_multifit.h")), (
        "GSL library headers not found. Was libgsl-dev installed?"
    )

    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", BINARY,
         "-lgsl", "-lgslcblas", "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert compile_result.returncode == 0, (
        f"train.c failed to compile.\nstdout:\n{compile_result.stdout}\n"
        f"stderr:\n{compile_result.stderr}"
    )

    # Confirm that the executable actually calls a GSL numerical/modeling API,
    # rather than merely linking unused libraries.
    symbols = subprocess.run(
        ["nm", "-D", BINARY], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=10, check=True
    ).stdout
    assert re.search(r"\bU\s+gsl_(?:multifit|linalg|blas)_", symbols), (
        "The compiled program does not use a GSL regression/linear-algebra API"
    )

    original_dataset = open(DATASET, "rb").read()
    output_existed = os.path.exists(OUTPUT)
    original_output = open(OUTPUT, "rb").read() if output_existed else None

    try:
        # Preserve the original coefficient assertions, but require the submitted
        # executable to regenerate the file in the exact instructed format.
        with open(DATASET, "wb") as f:
            f.write(original_dataset)
        run_and_check(["2.1462", "0.2248", "-0.0968"])

        # Exercise parsing, row rejection, and regression on unpredictable data.
        rng = random.Random(int.from_bytes(os.urandom(16), "big"))
        for _ in range(2):
            csv_text, valid_rows = make_random_dataset(rng)
            with open(DATASET, "w", encoding="utf-8") as f:
                f.write(csv_text)
            expected = [format(v, ".4f") for v in solve_ols(valid_rows)]
            run_and_check(expected)
    finally:
        with open(DATASET, "wb") as f:
            f.write(original_dataset)
        if output_existed:
            with open(OUTPUT, "wb") as f:
                f.write(original_output)
        elif os.path.lexists(OUTPUT):
            os.remove(OUTPUT)
        if os.path.exists(BINARY):
            os.remove(BINARY)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
