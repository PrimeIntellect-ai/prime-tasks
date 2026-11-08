#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import math
import os
import random
import secrets
import subprocess

BINARY_PATH = "/home/user/validator"
SOURCE_PATH = "/home/user/validator.c"
CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"
REF_VECTOR = (2.0, -1.0, 2.0)
THRESHOLD = 0.85


def run_validator(filepath):
    return subprocess.run(
        [BINARY_PATH, str(filepath)], capture_output=True, timeout=5
    ).returncode


def test_binary_exists_and_executable():
    """Check if the compiled binary exists and is executable."""
    assert os.path.isfile(BINARY_PATH), (
        f"Compiled binary not found at {BINARY_PATH}. Did you compile your C program?"
    )
    assert os.access(BINARY_PATH, os.X_OK), f"File at {BINARY_PATH} is not executable."
    assert os.path.isfile(SOURCE_PATH), f"C source not found at {SOURCE_PATH}."
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled validator must be an ELF executable."


def test_clean_corpus_accepted():
    """Ensure all clean CSV files exit with status code 0."""
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.csv"))
    assert clean_files, f"No CSV files found in {CLEAN_DIR}."

    rejected_files = []
    for filepath in clean_files:
        if run_validator(filepath) != 0:
            rejected_files.append(os.path.basename(filepath))

    assert not rejected_files, (
        f"{len(rejected_files)} of {len(clean_files)} clean files were incorrectly rejected "
        f"(expected exit code 0): {', '.join(rejected_files)}"
    )


def test_evil_corpus_rejected():
    """Ensure all evil/corrupted CSV files exit with status code 1."""
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.csv"))
    assert evil_files, f"No CSV files found in {EVIL_DIR}."

    wrong_status = []
    for filepath in evil_files:
        status = run_validator(filepath)
        if status != 1:
            wrong_status.append(f"{os.path.basename(filepath)} (status {status})")

    assert not wrong_status, (
        f"{len(wrong_status)} of {len(evil_files)} evil files returned the wrong status "
        f"(expected exit code 1): {', '.join(wrong_status)}"
    )


def cosine(vector):
    dot = sum(a * b for a, b in zip(vector, REF_VECTOR))
    vector_mag = math.sqrt(sum(v * v for v in vector))
    ref_mag = math.sqrt(sum(v * v for v in REF_VECTOR))
    if vector_mag == 0.0:
        return None
    return dot / (vector_mag * ref_mag)


def expected_status(rows):
    for vector in rows:
        score = cosine(vector)
        if score is None or score < THRESHOLD:
            return 1
    return 0


def test_runtime_generated_csvs(tmp_path):
    """Exercise both outcomes using unpredictable files in one neutral directory."""
    rng = random.SystemRandom()
    cases = []

    zero_rows = [REF_VECTOR, (0.0, 0.0, 0.0), (4.0, -2.0, 4.0)]
    cases.append((zero_rows, expected_status(zero_rows)))

    accepted = 0
    rejected = 1
    while accepted < 12 or rejected < 12:
        candidate = tuple(rng.uniform(-20.0, 20.0) for _ in range(3))
        score = cosine(candidate)
        if score is None or abs(score - THRESHOLD) < 0.05:
            continue

        rows = [
            tuple(v * rng.uniform(0.5, 3.0) for v in REF_VECTOR),
            candidate,
            tuple(v * rng.uniform(0.5, 3.0) for v in REF_VECTOR),
        ]
        status = expected_status(rows)
        if status == 0 and accepted < 12:
            cases.append((rows, status))
            accepted += 1
        elif status == 1 and rejected < 12:
            cases.append((rows, status))
            rejected += 1

    generated = []
    for rows, expected in cases:
        filepath = tmp_path / (secrets.token_hex(12) + ".csv")
        with open(filepath, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["id", "x", "y", "z"])
            for row_id, vector in enumerate(rows, 1):
                writer.writerow([row_id, *vector])
        generated.append((filepath, expected))

    rng.shuffle(generated)
    failures = []
    for filepath, expected in generated:
        actual = run_validator(filepath)
        if actual != expected:
            failures.append(f"{filepath.name}: expected {expected}, got {actual}")

    assert not failures, "Runtime-generated validation failures: " + "; ".join(failures)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
