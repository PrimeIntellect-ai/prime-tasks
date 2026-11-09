#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import secrets
import shutil
import subprocess

import pytest

BINARY_PATH = "/home/user/filter_model/target/release/filter_model"
CLEAN_DIR = "/app/data/clean/"
EVIL_DIR = "/app/data/evil/"
LEARNING_RATE = 0.003
MAX_ITERATIONS = 200
TOLERANCE = 1e-5


def test_binary_exists():
    assert os.path.exists(BINARY_PATH), f"Binary not found at {BINARY_PATH}"
    assert os.path.isfile(BINARY_PATH), f"Path {BINARY_PATH} is not a file"
    assert os.access(BINARY_PATH, os.X_OK), f"Binary at {BINARY_PATH} is not executable"


def test_clean_corpus():
    assert os.path.exists(CLEAN_DIR), f"Clean directory {CLEAN_DIR} is missing"
    files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.csv')]
    assert len(files) > 0, f"No CSV files found in {CLEAN_DIR}"

    failed_files = []
    for file in files:
        filepath = os.path.join(CLEAN_DIR, file)
        try:
            res = subprocess.run([BINARY_PATH, filepath], capture_output=True, text=True, timeout=5)
            output = res.stdout.strip()
            if output != "CLEAN":
                failed_files.append((file, output))
        except Exception as e:
            failed_files.append((file, str(e)))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(files)} clean modified/rejected.\n"
        error_msg += "Offending files:\n"
        for f, out in failed_files:
            error_msg += f"  {f}: got '{out}'\n"
        pytest.fail(error_msg)


def test_evil_corpus():
    assert os.path.exists(EVIL_DIR), f"Evil directory {EVIL_DIR} is missing"
    files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.csv')]
    assert len(files) > 0, f"No CSV files found in {EVIL_DIR}"

    failed_files = []
    for file in files:
        filepath = os.path.join(EVIL_DIR, file)
        try:
            res = subprocess.run([BINARY_PATH, filepath], capture_output=True, text=True, timeout=5)
            output = res.stdout.strip()
            if output != "EVIL":
                failed_files.append((file, output))
        except Exception as e:
            failed_files.append((file, str(e)))

    if failed_files:
        error_msg = f"{len(failed_files)} of {len(files)} evil bypassed.\n"
        error_msg += "Offending files:\n"
        for f, out in failed_files:
            error_msg += f"  {f}: got '{out}'\n"
        pytest.fail(error_msg)


def run_exact(path):
    res = subprocess.run(
        [BINARY_PATH, str(path)], capture_output=True, text=True, timeout=5
    )
    assert res.returncode == 0, f"nonzero exit status {res.returncode}: {res.stderr!r}"
    assert res.stdout in ("CLEAN\n", "EVIL\n"), f"invalid stdout: {res.stdout!r}"
    return res.stdout[:-1]


def reference_label(rows):
    n = len(rows)
    m = 0.0
    c = 0.0
    previous = None

    for _ in range(MAX_ITERATIONS):
        errors = [m * x + c - y for x, y in rows]
        mse = sum(e * e for e in errors) / (2.0 * n)
        if not math.isfinite(mse):
            return "EVIL"
        if previous is not None and abs(previous - mse) < TOLERANCE:
            return "CLEAN"

        dm = sum(e * x for e, (x, _) in zip(errors, rows)) / n
        dc = sum(errors) / n
        m -= LEARNING_RATE * dm
        c -= LEARNING_RATE * dc
        if not math.isfinite(m) or not math.isfinite(c):
            return "EVIL"
        previous = mse

    return "EVIL"


def write_csv(path, rows):
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write("x,y\n")
        for x, y in rows:
            f.write(f"{x:.17g},{y:.17g}\n")


def test_corpus_labels_do_not_depend_on_directory_name(tmp_path):
    cases = []
    for directory, expected in ((CLEAN_DIR, "CLEAN"), (EVIL_DIR, "EVIL")):
        files = sorted(f for f in os.listdir(directory) if f.endswith(".csv"))
        for source_name in files[:5]:
            destination = tmp_path / (secrets.token_hex(16) + ".csv")
            shutil.copyfile(os.path.join(directory, source_name), destination)
            cases.append((destination, expected))

    random.SystemRandom().shuffle(cases)
    for path, expected in cases:
        assert run_exact(path) == expected, f"wrong result for relocated CSV {path.name}"


def test_fresh_datasets_against_gradient_descent_oracle(tmp_path):
    rng = random.Random(secrets.randbits(128))
    datasets = []

    # Very small targets converge immediately under the specified tolerance.
    for _ in range(4):
        rows = []
        slope = rng.uniform(-0.008, 0.008)
        intercept = rng.uniform(-0.008, 0.008)
        for _ in range(80):
            x = rng.uniform(-2.0, 2.0)
            y = slope * x + intercept + rng.uniform(-1e-4, 1e-4)
            rows.append((x, y))
        datasets.append(rows)

    # Well-conditioned, centered datasets converge after multiple updates.
    for _ in range(4):
        rows = []
        slope = rng.uniform(1.0, 4.0) * rng.choice((-1.0, 1.0))
        for _ in range(40):
            x = rng.uniform(12.0, 22.0)
            rows.append((x, slope * x))
            rows.append((-x, -slope * x))
        rng.shuffle(rows)
        datasets.append(rows)

    # Ordinary-scale targets remain above the convergence threshold at the limit.
    for _ in range(5):
        rows = []
        slope = rng.uniform(1.0, 4.0) * rng.choice((-1.0, 1.0))
        intercept = rng.uniform(0.7, 2.0) * rng.choice((-1.0, 1.0))
        for _ in range(80):
            x = rng.uniform(-1.0, 1.0)
            y = slope * x + intercept + rng.uniform(-0.05, 0.05)
            rows.append((x, y))
        datasets.append(rows)

    # Extreme feature scales trigger numerical instability.
    for _ in range(3):
        rows = []
        slope = rng.uniform(0.5, 3.0)
        for _ in range(80):
            x = rng.uniform(-2000.0, 2000.0)
            y = slope * x + rng.uniform(-1.0, 1.0)
            rows.append((x, y))
        datasets.append(rows)

    cases = []
    for rows in datasets:
        path = tmp_path / (secrets.token_hex(16) + ".csv")
        write_csv(path, rows)
        cases.append((path, reference_label(rows)))

    labels = {label for _, label in cases}
    assert labels == {"CLEAN", "EVIL"}, f"generated suite lacks both labels: {labels}"
    random.SystemRandom().shuffle(cases)

    for path, expected in cases:
        actual = run_exact(path)
        assert actual == expected, f"expected {expected}, got {actual} for {path.name}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
