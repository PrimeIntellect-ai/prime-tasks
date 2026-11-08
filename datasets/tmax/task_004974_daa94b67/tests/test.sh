#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import random
import secrets
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/detect.sh"
MEANS = (10.0, -5.5, 3.14)
STDS = (2.5, 1.2, 0.5)


def run_detector(path):
    return subprocess.run(
        [SCRIPT_PATH, path],
        capture_output=True,
        timeout=10,
    ).returncode


def test_detect_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable."


def test_clean_corpus():
    clean_dir = "/app/corpus/clean/"
    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    assert len(clean_files) > 0, f"No CSV files found in {clean_dir}."

    failed_files = []
    for path in clean_files:
        if run_detector(path) != 0:
            failed_files.append(os.path.basename(path))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(clean_files)} clean files rejected "
            f"(expected exit code 0). Offending files: {', '.join(failed_files)}"
        )


def test_evil_corpus():
    evil_dir = "/app/corpus/evil/"
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))
    assert len(evil_files) > 0, f"No CSV files found in {evil_dir}."

    failed_files = []
    for path in evil_files:
        if run_detector(path) != 1:
            failed_files.append(os.path.basename(path))

    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(evil_files)} evil files bypassed "
            f"(expected exit code 1). Offending files: {', '.join(failed_files)}"
        )


def test_fresh_unlabelled_csv_inputs():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    root = tempfile.mkdtemp(prefix="vectors_", dir="/tmp")
    cases = []

    # Generate previously unseen files with random directions and distances on
    # both sides of the 2.50 boundary. Symmetric rows make the intended centroid
    # independent of individual-row values and exercise actual averaging.
    radii = [0.0, 0.35, 0.9, 1.6, 2.2, 2.42, 2.62, 2.9, 3.8, 5.0]
    for index in range(30):
        radius = rng.choice(radii)
        direction = [rng.gauss(0.0, 1.0) for _ in range(3)]
        length = math.sqrt(sum(x * x for x in direction))
        direction = [x / length for x in direction]
        centroid = [
            MEANS[i] + STDS[i] * radius * direction[i]
            for i in range(3)
        ]

        rows = [centroid]
        for _ in range(rng.randint(3, 8)):
            delta = [rng.uniform(-8.0, 8.0) * STDS[i] for i in range(3)]
            rows.append([centroid[i] + delta[i] for i in range(3)])
            rows.append([centroid[i] - delta[i] for i in range(3)])
        rng.shuffle(rows)

        path = os.path.join(root, secrets.token_hex(12) + ".csv")
        with open(path, "w", encoding="ascii") as handle:
            for row in rows:
                handle.write(",".join(f"{value:.9f}" for value in row) + "\n")

        # Derive the expected result from the exact serialized values presented
        # to the submission rather than trusting the generation label.
        parsed = []
        with open(path, encoding="ascii") as handle:
            for line in handle:
                parsed.append([float(value) for value in line.strip().split(",")])
        actual_centroid = [
            sum(row[i] for row in parsed) / len(parsed) for i in range(3)
        ]
        distance = math.sqrt(sum(
            (abs(actual_centroid[i] - MEANS[i]) / STDS[i]) ** 2
            for i in range(3)
        ))
        expected = 0 if distance <= 2.50 else 1
        cases.append((path, expected, distance))

    rng.shuffle(cases)
    failures = []
    for path, expected, distance in cases:
        actual = run_detector(path)
        if actual != expected:
            failures.append(
                f"{os.path.basename(path)}: distance={distance:.6f}, "
                f"expected={expected}, actual={actual}"
            )

    if failures:
        pytest.fail("Fresh CSV classification failures:\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
