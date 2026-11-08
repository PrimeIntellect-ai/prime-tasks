#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest

EXECUTABLE = "/home/user/classifier"
SOURCE = "/home/user/classifier.cpp"


def run_classifier(executable, csv_path):
    result = subprocess.run(
        [executable, csv_path],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"classifier exited with {result.returncode}: {result.stderr}"
    )
    assert result.stdout in ("CLEAN\n", "EVIL\n"), (
        f"classifier output must be exactly CLEAN or EVIL plus a newline; got {result.stdout!r}"
    )
    return result.stdout[:-1]


def test_classifier_exists():
    assert os.path.isfile(EXECUTABLE), "/home/user/classifier executable is missing"
    assert os.access(EXECUTABLE, os.X_OK), "/home/user/classifier is not executable"


def test_source_exists_and_compiles():
    assert os.path.isfile(SOURCE), "/home/user/classifier.cpp is missing"
    assert os.path.getsize(SOURCE) > 0, "/home/user/classifier.cpp is empty"

    output = "/tmp/classifier_from_submitted_source"
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", output],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"classifier.cpp does not compile: {result.stderr}"
    assert os.path.isfile(output) and os.access(output, os.X_OK)


def test_adversarial_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"{clean_dir} directory is missing"
    assert os.path.isdir(evil_dir), f"{evil_dir} directory is missing"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.csv')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.csv')]

    failed_clean = []
    failed_evil = []

    for cf in clean_files:
        result = subprocess.run([EXECUTABLE, cf], capture_output=True, text=True)
        if result.stdout.strip() != "CLEAN":
            failed_clean.append(os.path.basename(cf))

    for ef in evil_files:
        result = subprocess.run([EXECUTABLE, ef], capture_output=True, text=True)
        if result.stdout.strip() != "EVIL":
            failed_evil.append(os.path.basename(ef))

    errors = []
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean modified: {', '.join(failed_clean)}")

    assert not errors, " | ".join(errors)


def make_case(directory, rng, n, corruption_rate, distractors_fractional):
    column_count = rng.randint(3, 6)
    selected_column = rng.randrange(column_count)
    corrupt_count = round(n * corruption_rate)
    corrupt_rows = set(rng.sample(range(n), corrupt_count))

    rows = []
    offset = rng.randint(1000, 9000)
    for i in range(n):
        row = []
        for column in range(column_count):
            if column == selected_column:
                # This column has overwhelmingly the largest variance.
                value = float(offset + i * rng.randint(17, 29))
                if i in corrupt_rows:
                    value += rng.choice((0.25, 0.375, 0.5, -0.25))
            else:
                # Distractor columns have tiny variance and can deliberately have
                # the opposite integer/fractional character from the selected one.
                value = float((i + column) % 4)
                if distractors_fractional:
                    value += rng.choice((0.125, 0.25, 0.375))
            row.append(value)
        rows.append(row)

    rng.shuffle(rows)
    path = os.path.join(directory, secrets.token_hex(12) + ".csv")
    with open(path, "w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(",".join(format(value, ".8f") for value in row) + "\n")

    posterior_for_observed_rate = (corrupt_count + 1.0) / (n + 1.0 + 50.0)
    expected = "EVIL" if posterior_for_observed_rate > 0.03 else "CLEAN"
    return path, expected


def test_randomized_content_and_algorithm():
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    with tempfile.TemporaryDirectory(prefix="classifier_inputs_") as directory:
        cases = [
            # Highest-variance column is clean while every distractor is fractional.
            make_case(directory, rng, 220, 0.0, True),
            # Highest-variance column is heavily corrupted while distractors are integers.
            make_case(directory, rng, 220, 0.45, False),
            # Rates safely below and above the configured Bayesian threshold.
            make_case(directory, rng, 260, 0.015, False),
            make_case(directory, rng, 260, 0.065, False),
            make_case(directory, rng, 310, 0.0, True),
            make_case(directory, rng, 310, 0.30, False),
        ]
        rng.shuffle(cases)

        executables = [EXECUTABLE, "/tmp/classifier_from_submitted_source"]
        for executable in executables:
            for csv_path, expected in cases:
                actual = run_classifier(executable, csv_path)
                assert actual == expected, (
                    f"wrong classification for generated CSV {os.path.basename(csv_path)}: "
                    f"expected {expected}, got {actual}"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
