#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import math
import os
import secrets
import subprocess
import tempfile

import pytest

BINARY_PATH = "/home/user/filter_logs/target/release/filter_logs"
CLEAN_DIR = "/app/clean"
EVIL_DIR = "/app/evil"
THRESHOLD = 250.5


def test_binary_exists():
    assert os.path.exists(BINARY_PATH), f"Executable not found at {BINARY_PATH}"
    assert os.path.isfile(BINARY_PATH), f"{BINARY_PATH} is not a file"
    assert os.access(BINARY_PATH, os.X_OK), f"{BINARY_PATH} is not executable"


def test_adversarial_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.csv"))
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.csv"))

    assert len(clean_files) > 0, f"No clean files found in {CLEAN_DIR}"
    assert len(evil_files) > 0, f"No evil files found in {EVIL_DIR}"

    clean_failed = []
    for f in clean_files:
        result = subprocess.run([BINARY_PATH, f], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(f))

    evil_failed = []
    for f in evil_files:
        result = subprocess.run([BINARY_PATH, f], capture_output=True)
        if result.returncode != 1:
            evil_failed.append(os.path.basename(f))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean files modified/rejected (expected exit 0). Offending files: {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil files bypassed (expected exit 1). Offending files: {', '.join(evil_failed)}")

    if errors:
        pytest.fail("Adversarial corpus validation failed:\n" + "\n".join(errors))


def _write_csv(path, products, rng):
    fields = ["run_id", "inference_time_ms", "batch_size", "ignored_metric"]
    rng.shuffle(fields)
    rows = []
    for index, product in enumerate(products, 1):
        batch_size = rng.randint(1, 32)
        rows.append({
            "run_id": str(index),
            "inference_time_ms": format(product / batch_size, ".15g"),
            "batch_size": str(batch_size),
            "ignored_metric": format(rng.random(), ".8g"),
        })

    with open(path, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    # Derive the expected answer from the exact values written to the CSV.
    with open(path, newline="") as handle:
        parsed = list(csv.DictReader(handle))
    mean = math.fsum(
        float(row["inference_time_ms"]) * float(row["batch_size"])
        for row in parsed
    ) / len(parsed)
    return 1 if mean > THRESHOLD else 0


def test_generated_csvs_are_classified_from_contents():
    rng = secrets.SystemRandom()
    cases = [
        [250.5],
        [250.5001],
        [200.0, 301.0],
        [250.5, 250.5004],
    ]

    # Each randomized case has products on both sides of its target mean, so
    # classification requires computing the mean rather than inspecting one row.
    for index in range(20):
        target = THRESHOLD + (1 if index % 2 else -1) * rng.uniform(0.25, 80.0)
        products = [target]
        for _ in range(rng.randint(1, 4)):
            deviation = rng.uniform(1.0, min(220.0, target - 0.01))
            products.extend([target - deviation, target + deviation])
        rng.shuffle(products)
        cases.append(products)

    rng.shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix="classifier_cases_") as directory:
        generated = []
        for products in cases:
            path = os.path.join(directory, secrets.token_hex(12) + ".csv")
            expected = _write_csv(path, products, rng)
            generated.append((path, expected))

        rng.shuffle(generated)
        for path, expected in generated:
            result = subprocess.run(
                [BINARY_PATH, path], capture_output=True, timeout=5
            )
            if result.returncode != expected:
                failures.append(
                    f"{os.path.basename(path)}: expected {expected}, got {result.returncode}"
                )

    if failures:
        pytest.fail("Generated CSV validation failed:\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
