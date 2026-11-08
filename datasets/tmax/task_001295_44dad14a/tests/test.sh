#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import secrets
import subprocess
import tempfile
from decimal import Decimal

import pytest

EXECUTABLE = "/home/user/loc_check"
SOURCE = "/home/user/loc_check.c"
THRESHOLD = Decimal("420.00")
FORBIDDEN = "{{INJECT}}"


def run_checker(path, *extra):
    return subprocess.run(
        [EXECUTABLE, path, *extra],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=3,
    ).returncode


def test_executable_exists():
    """Verify that the requested C source and compiled executable exist."""
    assert os.path.isfile(SOURCE), f"C source not found at {SOURCE}"
    assert os.path.exists(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.path.isfile(EXECUTABLE), f"File at {EXECUTABLE} is not a regular file"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "loc_check is not a compiled executable"


def test_clean_corpus():
    """Verify that all original clean corpus files are accepted (exit code 0)."""
    clean_dir = "/app/corpus/clean/"
    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    assert len(clean_files) > 0, f"No clean CSV files found in {clean_dir}"

    failed_files = []
    for file_path in clean_files:
        if run_checker(file_path) != 0:
            failed_files.append(os.path.basename(file_path))
    if failed_files:
        pytest.fail(
            f"{len(failed_files)} of {len(clean_files)} clean files were incorrectly "
            f"rejected (exit code != 0): {', '.join(failed_files)}"
        )


def test_evil_corpus():
    """Verify that all original evil corpus files are rejected (exit code != 0)."""
    evil_dir = "/app/corpus/evil/"
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))
    assert len(evil_files) > 0, f"No evil CSV files found in {evil_dir}"

    bypassed_files = []
    for file_path in evil_files:
        if run_checker(file_path) == 0:
            bypassed_files.append(os.path.basename(file_path))
    if bypassed_files:
        pytest.fail(
            f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed the "
            f"filter (exit code == 0): {', '.join(bypassed_files)}"
        )


def oracle(rows):
    if any(FORBIDDEN in translation for _, _, translation in rows):
        return 1

    for i, (_, value, _) in enumerate(rows):
        if value != "MISSING":
            continue

        left = i - 1
        while left >= 0 and rows[left][1] == "MISSING":
            left -= 1
        right = i + 1
        while right < len(rows) and rows[right][1] == "MISSING":
            right += 1
        assert left >= 0 and right < len(rows), "Verifier generated an unbounded gap"

        interpolated = (Decimal(rows[left][1]) + Decimal(rows[right][1])) / Decimal(2)
        if interpolated > THRESHOLD:
            return 1
    return 0


def write_case(directory, rows):
    path = os.path.join(directory, secrets.token_hex(12) + ".csv")
    with open(path, "w", encoding="utf-8", newline="") as f:
        for timestamp, value, translation in rows:
            f.write(f"{timestamp},{value},{translation}\n")
    return path


def make_rows(a, b, missing_count=1, translations=None):
    if translations is None:
        translations = ["Alpha"] + ["Gap"] * missing_count + ["Omega"]
    values = [str(a)] + ["MISSING"] * missing_count + [str(b)]
    base = secrets.randbelow(900000) + 1000
    return [(str(base + i), values[i], translations[i]) for i in range(len(values))]


def test_hidden_generated_cases():
    """Exercise the image-defined interpolation, strict threshold, and substring rules."""
    rng = random.SystemRandom()
    cases = []

    # Boundary behavior and cases that distinguish interpolated values from raw values.
    cases.append(make_rows("400.00", "440.00"))                 # mean exactly 420: clean
    cases.append(make_rows("400.00", "440.02"))                 # mean 420.01: evil
    cases.append(make_rows("100.00", "740.00", 2))              # two gaps, mean 420: clean
    cases.append(make_rows("100.00", "740.02", 3))              # consecutive gaps: evil
    cases.append([
        ("11", "9999.00", "Large raw values are allowed"),
        ("12", "-5000.00", "No interpolation here"),
    ])
    cases.append(make_rows("-900.00", "100.00"))

    # Near-matches must not be treated as the exact forbidden substring.
    cases.append([
        ("21", "1.0", "{INJECT}"),
        ("22", "2.0", "{{inject}}"),
        ("23", "3.0", "{{INJECT}"),
    ])

    # Random arithmetic cases prevent recognition of a fixed visible corpus.
    for _ in range(14):
        center = Decimal(rng.randrange(-20000, 42001)) / Decimal(100)
        delta = Decimal(rng.randrange(1, 50000)) / Decimal(100)
        cases.append(make_rows(center - delta, center + delta, rng.randrange(1, 4)))

    for _ in range(14):
        center = Decimal(rng.randrange(42001, 65001)) / Decimal(100)
        delta = Decimal(rng.randrange(1, 50000)) / Decimal(100)
        cases.append(make_rows(center - delta, center + delta, rng.randrange(1, 4)))

    # Forbidden text is tested at varying positions and independently of interpolation.
    for _ in range(10):
        prefix = secrets.token_hex(rng.randrange(0, 8))
        suffix = secrets.token_hex(rng.randrange(0, 8))
        rows = make_rows("10.00", "20.00", rng.randrange(1, 3))
        target = rng.randrange(len(rows))
        timestamp, value, _ = rows[target]
        rows[target] = (timestamp, value, prefix + FORBIDDEN + suffix)
        cases.append(rows)

    rng.shuffle(cases)
    assert any(oracle(rows) == 0 for rows in cases)
    assert any(oracle(rows) == 1 for rows in cases)

    with tempfile.TemporaryDirectory(prefix=secrets.token_hex(8) + "_") as directory:
        generated = [(write_case(directory, rows), oracle(rows)) for rows in cases]
        rng.shuffle(generated)
        failures = []
        for path, expected in generated:
            actual = run_checker(path)
            if actual != expected:
                failures.append((os.path.basename(path), expected, actual))
        assert not failures, f"Generated adversarial cases failed: {failures[:8]}"


def test_exactly_one_argument_interface():
    with tempfile.TemporaryDirectory(prefix=secrets.token_hex(8) + "_") as directory:
        rows = make_rows("100.00", "200.00")
        path1 = write_case(directory, rows)
        path2 = write_case(directory, rows)
        no_arg = subprocess.run(
            [EXECUTABLE], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3
        ).returncode
        two_args = subprocess.run(
            [EXECUTABLE, path1, path2],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
        ).returncode
        assert no_arg != 0, "loc_check accepted an invocation with no CSV argument"
        assert two_args != 0, "loc_check accepted an invocation with two CSV arguments"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
