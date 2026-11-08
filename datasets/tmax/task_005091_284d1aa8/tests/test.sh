#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import random
import secrets
import subprocess
import tempfile

import pytest


def test_detector_script_exists_and_executable():
    script_path = "/home/user/detector.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_adversarial_corpus():
    script_path = "/home/user/detector.sh"

    clean_dir = "/app/clean"
    evil_dir = "/app/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))

    assert len(clean_files) > 0, "No clean files found."
    assert len(evil_files) > 0, "No evil files found."

    rejected_clean = []
    bypassed_evil = []

    for clean_file in clean_files:
        result = subprocess.run([script_path, clean_file], capture_output=True)
        if result.returncode != 0:
            rejected_clean.append(os.path.basename(clean_file))

    for evil_file in evil_files:
        result = subprocess.run([script_path, evil_file], capture_output=True)
        if result.returncode != 1:
            bypassed_evil.append(os.path.basename(evil_file))

    error_messages = []
    if rejected_clean:
        error_messages.append(f"{len(rejected_clean)} of {len(clean_files)} clean files rejected: {', '.join(rejected_clean)}")
    if bypassed_evil:
        error_messages.append(f"{len(bypassed_evil)} of {len(evil_files)} evil files bypassed: {', '.join(bypassed_evil)}")

    if error_messages:
        pytest.fail(" | ".join(error_messages))


def expected_status(rows):
    for _, alpha, beta in rows:
        a = 0 if alpha is None else alpha
        b = 0 if beta is None else beta
        if 5 * a - 3 * b + 10 > 100:
            return 1
    return 0


def test_generated_hidden_cases():
    script_path = "/home/user/detector.sh"
    rng = random.SystemRandom()

    # Boundary and feature-isolation cases, including missing values and cases
    # where the corrupting row is not consistently first or last.
    cases = [
        [(1, 18, 0)],
        [(1, 19, 0)],
        [(1, None, -30)],
        [(1, None, -31)],
        [(1, 25, 12)],
        [(1, 25, 11)],
        [(1, None, None), (2, -10, -47), (3, 0, 0)],
        [(1, 0, 0), (2, 30, 40), (3, 22, 5)],
        [(1, 40, 50), (2, 0, None), (3, -20, -100)],
        [(1, -40, -40), (2, None, 4), (3, 12, None)],
    ]

    # Build fresh, unpredictable datasets and derive their answers directly
    # from the recovered pipeline specification.
    for _ in range(64):
        rows = []
        for row_id in range(1, rng.randint(2, 9)):
            alpha = None if rng.random() < 0.22 else rng.randint(-40, 45)
            beta = None if rng.random() < 0.22 else rng.randint(-50, 50)
            rows.append((row_id, alpha, beta))
        cases.append(rows)

    rng.shuffle(cases)
    workdir = tempfile.mkdtemp(prefix="corpus_", dir="/tmp")
    input_path = os.path.join(workdir, secrets.token_hex(12) + ".csv")
    failures = []

    for case_number, rows in enumerate(cases):
        with open(input_path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "feature_alpha", "feature_beta"])
            for row_id, alpha, beta in rows:
                writer.writerow([
                    row_id,
                    "" if alpha is None else alpha,
                    "" if beta is None else beta,
                ])

        expected = expected_status(rows)
        try:
            result = subprocess.run(
                [script_path, input_path], capture_output=True, timeout=5
            )
            actual = result.returncode
        except subprocess.TimeoutExpired:
            actual = "timeout"

        if actual != expected:
            failures.append(
                f"generated case {case_number}: expected exit {expected}, got {actual}"
            )

    if failures:
        pytest.fail(" | ".join(failures[:10]))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
