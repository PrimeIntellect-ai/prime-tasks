#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import subprocess
from fractions import Fraction

import pytest

SOURCE = "/home/user/compute_cov.c"
EXECUTABLE = "/home/user/compute_cov"
RESULT = "/home/user/covariance_result.txt"
RAW_TSV = "/home/user/etl_raw.tsv"
COMPILED_FROM_SOURCE = "/tmp/compute_cov_from_source"


def covariance(pairs):
    n = len(pairs)
    assert n >= 2
    sx = sum(x for x, _ in pairs)
    sy = sum(y for _, y in pairs)
    sxy = sum(x * y for x, y in pairs)
    return (Fraction(sxy, 1) - Fraction(sx * sy, n)) / (n - 1)


def format_covariance(value):
    negative = value < 0
    value = abs(value)
    scaled = value * 1000
    rounded = scaled.numerator // scaled.denominator
    remainder = scaled.numerator % scaled.denominator
    if remainder * 2 >= scaled.denominator:
        rounded += 1
    prefix = "-" if negative and rounded != 0 else ""
    return f"{prefix}{rounded // 1000}.{rounded % 1000:03d}"


def is_rounding_tie(value):
    scaled = abs(value) * 1000
    remainder = scaled.numerator % scaled.denominator
    return remainder * 2 == scaled.denominator


def run_program(path, pairs):
    input_data = "".join(f"{x} {y}\n" for x, y in pairs)
    completed = subprocess.run(
        [path], input=input_data, text=True, capture_output=True, timeout=5
    )
    assert completed.returncode == 0, (
        f"{path} exited with {completed.returncode}; stderr={completed.stderr!r}"
    )
    assert re.fullmatch(r"-?\d+\.\d{3}\n?", completed.stdout), (
        f"{path} did not print exactly one number with 3 decimal places: "
        f"{completed.stdout!r}"
    )
    return completed.stdout.strip()


@pytest.fixture(scope="session")
def rebuilt_program():
    completed = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE,
         "-o", COMPILED_FROM_SOURCE],
        text=True, capture_output=True, timeout=20
    )
    assert completed.returncode == 0, (
        f"C source failed to compile:\n{completed.stdout}\n{completed.stderr}"
    )
    return COMPILED_FROM_SOURCE


def test_compute_cov_c_exists():
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} does not exist."


def test_compute_cov_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Compiled executable {EXECUTABLE} does not exist."
    st = os.stat(EXECUTABLE)
    assert st.st_mode & stat.S_IXUSR, f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled ELF executable."


def test_covariance_result():
    assert os.path.isfile(RESULT), f"Result file {RESULT} does not exist."
    with open(RESULT, "r") as f:
        content = f.read().strip()
    assert content == "-0.600", (
        f"Expected covariance result to be '-0.600', but got '{content}'."
    )


def test_programs_compute_sample_covariance(rebuilt_program):
    cases = [
        [(1, 2), (2, 4), (3, 6)],
        [(-3, 7), (4, -2), (8, -5), (1, 3)],
        [(10, 1), (20, 5), (25, -2), (-4, 9), (7, 3)],
    ]

    rng = random.SystemRandom()
    while len(cases) < 8:
        pairs = [(rng.randint(-50, 50), rng.randint(-50, 50))
                 for _ in range(rng.randint(3, 10))]
        expected_value = covariance(pairs)
        if expected_value != 0 and not is_rounding_tie(expected_value):
            cases.append(pairs)

    for pairs in cases:
        expected = format_covariance(covariance(pairs))
        assert run_program(EXECUTABLE, pairs) == expected
        assert run_program(rebuilt_program, pairs) == expected


def test_tsv_tokenization_pipeline_result(rebuilt_program):
    pairs = []
    with open(RAW_TSV, "r", encoding="utf-8") as f:
        for line_number, line in enumerate(f, 1):
            line = line.rstrip("\n")
            left, separator, right = line.partition("\t")
            assert separator, f"TSV line {line_number} has no tab separator."
            pairs.append((len(left.split()), len(right.split())))

    assert len(pairs) >= 2, "The TSV must contain at least two rows."
    expected = format_covariance(covariance(pairs))
    assert expected == "-0.600"
    assert run_program(EXECUTABLE, pairs) == expected
    assert run_program(rebuilt_program, pairs) == expected

    with open(RESULT, "r", encoding="utf-8") as f:
        assert f.read().strip() == expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
