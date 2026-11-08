#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

HOME = "/home/user"
PROGRAM = f"{HOME}/mc_pi"
MODULUS = 2147483648


def reference_output(seed, n):
    state = seed
    inside = 0
    for _ in range(n):
        state = (1103515245 * state + 12345) % MODULUS
        x = state / 2147483648.0
        state = (1103515245 * state + 12345) % MODULUS
        y = state / 2147483648.0
        if x * x + y * y <= 1.0:
            inside += 1
    return f"{4.0 * inside / n:.6f}"


def run_program(seed, n):
    result = subprocess.run(
        [PROGRAM, str(seed), str(n)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"mc_pi failed for seed={seed}, N={n}: {result.stderr}"
    )
    assert result.stderr == "", f"mc_pi wrote unexpected stderr: {result.stderr!r}"
    assert re.fullmatch(r"[0-9]+\.[0-9]{6}\n?", result.stdout), (
        f"Output must contain only one value with exactly 6 decimal places; "
        f"got {result.stdout!r}"
    )
    return result.stdout.rstrip("\n")


def test_files_exist():
    assert os.path.isfile(f"{HOME}/mc_pi.c"), "/home/user/mc_pi.c is missing"
    assert os.path.isfile(f"{HOME}/Makefile"), "/home/user/Makefile is missing"
    assert os.path.isfile(f"{HOME}/scaling_report.txt"), "/home/user/scaling_report.txt is missing"


def test_makefile_and_compilation():
    if os.path.exists(PROGRAM):
        os.remove(PROGRAM)

    dry = subprocess.run(
        ["make", "-n", "-C", HOME], capture_output=True, text=True, timeout=20
    )
    assert dry.returncode == 0, f"make dry-run failed:\n{dry.stderr}"
    recipe = dry.stdout + dry.stderr
    assert re.search(r"(^|[\s/])gcc([\s]|$)", recipe), "Makefile must use gcc"
    for flag in ("-O3", "-Wall", "-Wextra", "-lm"):
        assert flag in recipe, f"Makefile compilation/link command is missing {flag}"

    result = subprocess.run(
        ["make", "-C", HOME], capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, f"make failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(PROGRAM), "make did not produce /home/user/mc_pi"
    assert os.access(PROGRAM, os.X_OK), "/home/user/mc_pi is not executable"


def test_mc_pi_execution():
    # Preserve the original fixed case, but verify its actual answer and several
    # independently derived cases, including unpredictable seeds and sizes.
    cases = [(42, 10000), (0, 1), (1, 37), (2147483647, 257)]
    rng = random.SystemRandom()
    cases.extend((rng.randrange(MODULUS), rng.randrange(300, 5001)) for _ in range(5))

    for seed, n in cases:
        actual = run_program(seed, n)
        expected = reference_output(seed, n)
        assert actual == expected, (
            f"Wrong estimate for seed={seed}, N={n}: got {actual}, expected {expected}"
        )


def test_argument_handling():
    bad_commands = [
        [PROGRAM],
        [PROGRAM, "42"],
        [PROGRAM, "42", "100", "extra"],
        [PROGRAM, "not-an-integer", "100"],
        [PROGRAM, "42", "not-an-integer"],
    ]
    for command in bad_commands:
        result = subprocess.run(command, capture_output=True, text=True, timeout=5)
        assert result.returncode != 0, f"Invalid arguments unexpectedly succeeded: {command}"


def test_scaling_report():
    with open(f"{HOME}/scaling_report.txt", "r", encoding="utf-8") as f:
        content = f.read()

    match = re.fullmatch(
        r"Slope: ([+-]?\d+\.\d{4})\nIntercept: ([+-]?\d+\.\d{4})\n?",
        content,
    )
    assert match is not None, (
        "scaling_report.txt must contain exactly the two requested lines, with "
        "slope and intercept rounded to exactly 4 decimal places"
    )

    slope = float(match.group(1))
    intercept = float(match.group(2))

    # Preserve the original report assertions.
    expected_slope = -1.0267
    expected_intercept = 5.2530
    assert math.isclose(slope, expected_slope, abs_tol=0.0005), (
        f"Slope {slope} is not close to {expected_slope}"
    )
    assert math.isclose(intercept, expected_intercept, abs_tol=0.0005), (
        f"Intercept {intercept} is not close to {expected_intercept}"
    )

    # Independently derive the five estimates and the OLS result from the stated
    # LCG instead of trusting constants copied into the report.
    ns = [10000, 20000, 30000, 40000, 50000]
    estimates = [float(reference_output(42, n)) for n in ns]
    xs = [math.log(n) for n in ns]
    ys = [math.log(abs(estimate - 3.1415926535)) for estimate in estimates]
    x_mean = sum(xs) / len(xs)
    y_mean = sum(ys) / len(ys)
    derived_slope = sum((x - x_mean) * (y - y_mean) for x, y in zip(xs, ys)) / sum(
        (x - x_mean) ** 2 for x in xs
    )
    derived_intercept = y_mean - derived_slope * x_mean

    assert match.group(1) == f"{derived_slope:.4f}", (
        f"Reported slope {match.group(1)} does not match derived OLS slope "
        f"{derived_slope:.4f}"
    )
    assert match.group(2) == f"{derived_intercept:.4f}", (
        f"Reported intercept {match.group(2)} does not match derived OLS intercept "
        f"{derived_intercept:.4f}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
