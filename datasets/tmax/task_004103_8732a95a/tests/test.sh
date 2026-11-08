#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import secrets
import subprocess
import tempfile
import glob

import pytest

BIN_PATH = "/home/user/validate_dataset"
SRC_PATH = "/home/user/validate_dataset.c"
BUILT_FROM_SOURCE = os.path.join(tempfile.gettempdir(), "validate_dataset_" + secrets.token_hex(12))


def expected_exit_code(csv_path):
    sum_x = 0.0
    sum_y = 0.0
    sum_xy = 0.0
    sum_x2 = 0.0
    sum_y2 = 0.0
    n = 0
    with open(csv_path, "r", encoding="utf-8") as f:
        next(f)
        for line in f:
            fields = line.strip().split(",")
            if len(fields) != 3:
                continue
            try:
                x, y, _ = map(float, fields)
            except ValueError:
                continue
            sum_x += x
            sum_y += y
            sum_xy += x * y
            sum_x2 += x * x
            sum_y2 += y * y
            n += 1

    assert n > 0
    mean_x = sum_x / n
    mean_y = sum_y / n
    cov_xy = (sum_xy / n) - (mean_x * mean_y)
    var_x = (sum_x2 / n) - (mean_x * mean_x)
    var_y = (sum_y2 / n) - (mean_y * mean_y)
    r = cov_xy / math.sqrt(var_x * var_y)
    return 1 if abs(r) > 0.99 else 0


def run_validator(binary, csv_path):
    return subprocess.run(
        [binary, csv_path], capture_output=True, timeout=5
    ).returncode


def write_correlated_csv(path, target_r, rng, n):
    # Construct centered, orthogonal vectors so the realized sample
    # correlation is approximately target_r rather than merely drawing from
    # a population having that requested correlation.
    x = [rng.gauss(0.0, 1.0) for _ in range(n)]
    q = [rng.gauss(0.0, 1.0) for _ in range(n)]
    mx = sum(x) / n
    mq = sum(q) / n
    x = [v - mx for v in x]
    q = [v - mq for v in q]
    xx = sum(v * v for v in x)
    projection = sum(a * b for a, b in zip(x, q)) / xx
    q = [b - projection * a for a, b in zip(x, q)]
    qq = sum(v * v for v in q)
    xn = [v / math.sqrt(xx) for v in x]
    qn = [v / math.sqrt(qq) for v in q]
    residual = math.sqrt(max(0.0, 1.0 - target_r * target_r))

    x_scale = 10.0 ** rng.uniform(-1.5, 1.5)
    y_scale = 10.0 ** rng.uniform(-1.5, 1.5)
    x_offset = rng.uniform(-20.0, 20.0)
    y_offset = rng.uniform(-20.0, 20.0)

    with open(path, "w", encoding="utf-8") as f:
        f.write("X,Y,Z\n")
        for i in range(n):
            xv = x_offset + x_scale * xn[i]
            yv = y_offset + y_scale * (target_r * xn[i] + residual * qn[i])
            z = rng.uniform(-100.0, 100.0)
            f.write(f"{xv:.17g},{yv:.17g},{z:.17g}\n")


def test_validate_dataset_binary_exists():
    assert os.path.exists(BIN_PATH), f"Binary missing at {BIN_PATH}. Did you compile your C program?"
    assert os.path.isfile(BIN_PATH), f"{BIN_PATH} is not a file."
    assert os.access(BIN_PATH, os.X_OK), f"{BIN_PATH} is not executable."

    assert os.path.exists(SRC_PATH), f"C source missing at {SRC_PATH}."
    assert os.path.isfile(SRC_PATH), f"{SRC_PATH} is not a file."
    compile_result = subprocess.run(
        ["gcc", "-O2", "-std=c11", SRC_PATH, "-o", BUILT_FROM_SOURCE, "-lm"],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        "validate_dataset.c did not compile: " + compile_result.stderr
    )
    assert os.path.isfile(BUILT_FROM_SOURCE)
    assert os.access(BUILT_FROM_SOURCE, os.X_OK)


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_files = sorted(glob.glob(os.path.join(clean_dir, "*.csv")))
    evil_files = sorted(glob.glob(os.path.join(evil_dir, "*.csv")))

    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}."
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}."

    failures = []
    for csv_path in clean_files + evil_files:
        expected = expected_exit_code(csv_path)
        actual = run_validator(BIN_PATH, csv_path)
        if actual != expected:
            failures.append(f"{os.path.basename(csv_path)}: expected {expected}, got {actual}")

    assert not failures, f"{len(failures)} corpus classifications incorrect: " + "; ".join(failures)


def test_generated_unlabelled_inputs():
    seed = int.from_bytes(os.urandom(16), "big")
    rng = random.Random(seed)
    test_dir = tempfile.mkdtemp(prefix="dataset_" + secrets.token_hex(8) + "_")

    # Exercise both signs, ordinary correlations, and values on both sides of
    # the clean 0.99 cutoff. Names and order contain no clean/evil labels.
    targets = [
        0.0, 0.3, -0.3, 0.8, -0.8, 0.97, -0.97,
        0.985, -0.985, 0.9895, -0.9895, 0.99, -0.99,
        0.9905, -0.9905, 0.993, -0.993, 0.999, -0.999,
    ]
    targets += [rng.uniform(-0.97, 0.97) for _ in range(5)]
    targets += [rng.choice((-1.0, 1.0)) * rng.uniform(0.992, 0.9995) for _ in range(5)]
    rng.shuffle(targets)

    cases = []
    expected_codes = set()
    for target in targets:
        path = os.path.join(test_dir, secrets.token_hex(16) + ".csv")
        write_correlated_csv(path, target, rng, rng.randint(37, 173))
        expected = expected_exit_code(path)
        expected_codes.add(expected)
        cases.append((path, expected))

    assert expected_codes == {0, 1}, "Generated suite must contain safe and evil data"

    failures = []
    for binary in (BIN_PATH, BUILT_FROM_SOURCE):
        for path, expected in cases:
            actual = run_validator(binary, path)
            if actual != expected:
                failures.append(
                    f"{os.path.basename(binary)} on {os.path.basename(path)}: "
                    f"expected {expected}, got {actual}"
                )
    assert not failures, f"{len(failures)} generated classifications incorrect: " + "; ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
