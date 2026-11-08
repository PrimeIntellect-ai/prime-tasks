#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from pathlib import Path

import pytest

RESULT_PATH = Path("/home/user/stable_result.txt")
READS_PATH = Path("/home/user/reads.txt")
SOURCE_PATH = Path("/home/user/kmer_density.go")
BINARY_PATH = Path("/tmp/kmer_density_submission")
FACTOR = 0.123456789


def expected_output(text):
    total = 0.0
    for line in text.splitlines():
        line = line.strip()
        if line:
            total += float(line) * FACTOR
    return f"{total:.12f}"


def run_submission():
    proc = subprocess.run(
        [str(BINARY_PATH)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, f"The submitted Go program failed:\n{proc.stderr}"
    return proc.stdout.strip()


@pytest.fixture(scope="session", autouse=True)
def build_submission():
    assert SOURCE_PATH.is_file(), f"File {SOURCE_PATH} is missing."
    proc = subprocess.run(
        ["go", "build", "-o", str(BINARY_PATH), str(SOURCE_PATH)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert proc.returncode == 0, f"Could not build {SOURCE_PATH}:\n{proc.stderr}"


def test_01_stable_result_and_program_on_original_input():
    result_path = "/home/user/stable_result.txt"
    reads_path = "/home/user/reads.txt"

    assert os.path.isfile(result_path), f"File {result_path} is missing. Did you redirect the output?"
    assert os.path.isfile(reads_path), f"File {reads_path} is missing."

    # Calculate expected sum in Python (float is IEEE 754 double precision, identical to Go's float64)
    expected_sum = 0.0
    with open(reads_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            val = float(line)
            expected_sum += val * 0.123456789

    expected_str = f"{expected_sum:.12f}"

    with open(result_path, "r") as f:
        actual_str = f.read().strip()

    assert actual_str == expected_str, (
        f"Numerical mismatch. Expected strictly sequential addition resulting in {expected_str}, "
        f"but got {actual_str} in {result_path}. Ensure the sum is accumulated in the exact order."
    )

    actual_program_output = run_submission()
    assert actual_program_output == expected_str, (
        f"Executing {SOURCE_PATH} on the original input produced {actual_program_output!r}, "
        f"but exact sequential accumulation requires {expected_str!r}."
    )


def exercise_hidden_input(lines, repetitions):
    original = READS_PATH.read_bytes()
    text = "\n".join(lines) + "\n"
    expected = expected_output(text)
    try:
        READS_PATH.write_text(text)
        for _ in range(repetitions):
            actual = run_submission()
            assert actual == expected, (
                f"Program output {actual!r}; exact input-order accumulation requires {expected!r}."
            )
    finally:
        READS_PATH.write_bytes(original)


def test_02_hidden_numeric_input():
    rng = secrets.SystemRandom()
    lines = []
    for _ in range(1200):
        numerator = rng.randrange(-10**12, 10**12)
        lines.append(f"{numerator / 10**6:.12f}")
    exercise_hidden_input(lines, repetitions=2)


def test_03_order_sensitive_hidden_input():
    rng = secrets.SystemRandom()
    lines = []
    # In sequential order, each large cancellation erases the preceding small
    # partial sum and leaves only the following small term. Reordered concurrent
    # reductions produce a detectably different result.
    for _ in range(2500):
        large = 10**16 + rng.randrange(0, 10**7)
        small = rng.randrange(1, 10000) / 1000.0
        lines.extend((str(large), str(-large), f"{small:.12f}"))
    exercise_hidden_input(lines, repetitions=3)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
