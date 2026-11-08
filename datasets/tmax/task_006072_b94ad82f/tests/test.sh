#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
from decimal import Decimal, localcontext
from fractions import Fraction

import pytest

SOLUTION = "/home/user/solution.go"
RESULTS = "/home/user/corrected_results.txt"
QUERIES = "/home/user/data/queries.log"
BINARY = "/tmp/submitted_metric_calc"

ORIGINAL_QUERIES = b"""1.0, 2.0, 3.0, 4.0, 5.0
10000.0, 10001.0, 10002.0
1000000000.0, 1000000001.0, 1000000002.0
999999998.0, 1000000000.0, 1000000002.0
5000000.5, 5000001.5
"""


def run_solution():
    if os.path.lexists(RESULTS):
        if os.path.isdir(RESULTS):
            raise AssertionError(f"Expected a file, but found a directory: {RESULTS}")
        os.unlink(RESULTS)

    completed = subprocess.run(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"Compiled solution exited with status {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )
    assert os.path.exists(RESULTS), "Running solution.go did not create corrected_results.txt"
    assert stat.S_ISREG(os.stat(RESULTS).st_mode), f"Expected a regular file: {RESULTS}"


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_submission():
    assert os.path.exists(SOLUTION), f"Missing required file: {SOLUTION}"
    assert os.path.isfile(SOLUTION), f"Expected a file, but found a directory: {SOLUTION}"

    completed = subprocess.run(
        ["go", "build", "-o", BINARY, SOLUTION],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, f"solution.go does not compile: {completed.stderr}"

    with open(QUERIES, "wb") as f:
        f.write(ORIGINAL_QUERIES)
    run_solution()

    yield

    # Leave the task's original input and corresponding output in place.
    with open(QUERIES, "wb") as f:
        f.write(ORIGINAL_QUERIES)
    try:
        run_solution()
    except Exception:
        pass


def test_solution_go_exists():
    """Verify that the user created the solution.go file."""
    path = "/home/user/solution.go"
    assert os.path.exists(path), f"Missing required file: {path}"
    assert os.path.isfile(path), f"Expected a file, but found a directory: {path}"


def test_corrected_results_exists():
    """Verify that the corrected_results.txt file exists."""
    path = "/home/user/corrected_results.txt"
    assert os.path.exists(path), f"Missing required file: {path}"
    assert os.path.isfile(path), f"Expected a file, but found a directory: {path}"


def test_corrected_results_content():
    """Verify that the corrected_results.txt file contains the correct sample variance calculations."""
    path = "/home/user/corrected_results.txt"
    expected_lines = [
        "2.50",
        "1.00",
        "1.00",
        "4.00",
        "0.50"
    ]

    with open(path, "r") as f:
        content = f.read().splitlines()

    # Filter out empty lines
    content = [line.strip() for line in content if line.strip()]

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines of output, but got {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual == expected, f"Line {i+1} is incorrect. Expected '{expected}', but got '{actual}'."


def sample_variance(values):
    n = len(values)
    mean = sum(values, Fraction(0)) / n
    return sum((value - mean) ** 2 for value in values) / (n - 1)


def safely_rounded(value):
    # Keep generated answers away from a two-decimal rounding boundary so
    # harmless floating-point noise in a stable float64 implementation is allowed.
    scaled = value * 100
    whole = scaled.numerator // scaled.denominator
    boundaries = [Fraction(whole, 1) - Fraction(1, 2),
                  Fraction(whole, 1) + Fraction(1, 2)]
    return min(abs(scaled - boundary) for boundary in boundaries) > Fraction(1, 4)


def format_fraction(value):
    with localcontext() as context:
        context.prec = 80
        decimal_value = Decimal(value.numerator) / Decimal(value.denominator)
        return format(decimal_value, ".2f")


def test_compiled_program_handles_unseen_large_inputs_stably():
    rng = secrets.SystemRandom()
    cases = []

    while len(cases) < 8:
        base = rng.randrange(8_000_000_000, 40_000_000_000)
        count = rng.randrange(3, 10)
        offsets = [rng.randrange(-2000, 2001) for _ in range(count)]
        values = [Fraction(base + offset, 1) for offset in offsets]
        variance = sample_variance(values)
        if safely_rounded(variance):
            cases.append((values, format_fraction(variance)))

    with open(QUERIES, "w") as f:
        for values, _ in cases:
            f.write(", ".join(str(value.numerator) for value in values) + "\n")

    run_solution()

    with open(RESULTS, "r") as f:
        actual = [line.strip() for line in f.read().splitlines() if line.strip()]
    expected = [answer for _, answer in cases]

    assert actual == expected, (
        "The compiled Go program did not compute stable sample variance for "
        f"unseen large-number queries. Expected {expected}, got {actual}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
