#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import secrets
import subprocess

import pytest

SOURCE = "/home/user/bootstrap_regression.c"
DATA = "/home/user/seq_data.csv"
RESULTS = "/home/user/regression_results.txt"
EXECUTABLE = "/tmp/bootstrap_regression_submission"

ORIGINAL_ROWS = [
    (0.35, 120),
    (0.41, 135),
    (0.45, 142),
    (0.50, 150),
    (0.55, 160),
    (0.60, 175),
    (0.65, 180),
    (0.70, 195),
]

BROAD_PATTERN = re.compile(
    r"^Slope:\s*([0-9\.-]+),\s*95%\s*CI:\s*\[([0-9\.-]+),\s*([0-9\.-]+)\]$"
)
STRICT_PATTERN = re.compile(
    r"^Slope: (-?\d+\.\d{2}), 95% CI: \[(-?\d+\.\d{2}), (-?\d+\.\d{2})\]$"
)


def write_csv(rows):
    with open(DATA, "w", encoding="utf-8") as f:
        f.write("GC,Length\n")
        for gc, length in rows:
            f.write(f"{gc:.3f},{length}\n")


def calculate_slope(rows):
    n = 8
    mean_x = sum(row[0] for row in rows) / n
    mean_y = sum(row[1] for row in rows) / n
    numerator = 0.0
    denominator = 0.0
    for x, y in rows:
        dx = x - mean_x
        numerator += dx * (y - mean_y)
        denominator += dx * dx
    assert denominator != 0.0
    return numerator / denominator


def expected_values(rows):
    libc = ctypes.CDLL(None)
    libc.srand.argtypes = [ctypes.c_uint]
    libc.rand.argtypes = []
    libc.rand.restype = ctypes.c_int
    libc.srand(42)

    slopes = []
    for _ in range(10000):
        sample = []
        for _ in range(8):
            sample.append(rows[libc.rand() % 8])
        slopes.append(calculate_slope(sample))
    slopes.sort()
    return calculate_slope(rows), slopes[250], slopes[9749]


def run_submission(rows):
    write_csv(rows)
    if os.path.exists(RESULTS):
        os.unlink(RESULTS)
    completed = subprocess.run(
        [EXECUTABLE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"Compiled program exited with status {completed.returncode}. "
        f"stderr: {completed.stderr}"
    )
    assert os.path.exists(RESULTS), f"Output file {RESULTS} does not exist."
    assert os.path.isfile(RESULTS), f"Path {RESULTS} is not a file."
    with open(RESULTS, "r", encoding="utf-8") as f:
        return f.read().strip()


@pytest.fixture(scope="session")
def compiled_program():
    completed = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-lm", "-o", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f"Failed to compile {SOURCE}. Compiler output:\n"
        f"{completed.stdout}{completed.stderr}"
    )
    assert os.path.isfile(EXECUTABLE)
    return EXECUTABLE


def test_c_source_exists():
    assert os.path.exists(SOURCE), f"C source file {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"Path {SOURCE} is not a file."


def test_regression_results_exists_and_format(compiled_program):
    content = run_submission(ORIGINAL_ROWS)
    match = BROAD_PATTERN.match(content)
    assert match is not None, (
        f"Content of {RESULTS} does not match the expected format: "
        f"'Slope: X.XX, 95% CI: [Y.YY, Z.ZZ]'. Found: {content}"
    )

    slope_str, lower_str, upper_str = match.groups()
    try:
        slope = float(slope_str)
        lower = float(lower_str)
        upper = float(upper_str)
    except ValueError:
        pytest.fail("Parsed values for slope or CI bounds are not valid floats.")

    assert abs(slope - 211.75) < 0.1, (
        f"Expected original slope around 211.75, but got {slope}."
    )
    assert 170.0 <= lower <= 180.0, (
        f"Expected lower bound between 170 and 180, but got {lower}."
    )
    assert 250.0 <= upper <= 265.0, (
        f"Expected upper bound between 250 and 265, but got {upper}."
    )


def test_program_computes_bootstrap_for_runtime_datasets(compiled_program):
    rng = secrets.SystemRandom()
    gc_values = [0.217, 0.294, 0.368, 0.443, 0.527, 0.611, 0.704, 0.823]

    cases = []
    for _ in range(2):
        rows = [(gc, rng.randrange(75, 351)) for gc in gc_values]
        rng.shuffle(rows)
        cases.append(rows)

    try:
        for rows in cases:
            expected = expected_values(rows)
            content = run_submission(rows)
            match = STRICT_PATTERN.match(content)
            assert match is not None, (
                "Program output must use exactly two decimal places and the format "
                f"'Slope: X.XX, 95% CI: [Y.YY, Z.ZZ]'. Found: {content}"
            )
            actual = tuple(float(value) for value in match.groups())
            labels = ("slope", "lower confidence bound", "upper confidence bound")
            for label, got, wanted in zip(labels, actual, expected):
                assert abs(got - wanted) <= 0.0051, (
                    f"Incorrect {label} for verifier-generated input: got {got:.2f}, "
                    f"expected {wanted:.2f}."
                )
    finally:
        write_csv(ORIGINAL_ROWS)
        try:
            run_submission(ORIGINAL_ROWS)
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
