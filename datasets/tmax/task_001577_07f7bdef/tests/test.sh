#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess

SOURCE_PATH = "/home/user/posterior.c"
RESULT_PATH = "/home/user/posterior_result.txt"
OBSERVATIONS_PATH = "/home/user/observations.txt"
EXPECTED_ORIGINAL = "beta1=2.207, beta2=1.831"
ORIGINAL_DATA = """4.1;1.0;1.01
8.2;2.0;1.98
12.0;3.0;3.05
16.5;4.0;3.95
20.1;5.0;5.02
"""


def test_c_source_exists():
    assert os.path.isfile(SOURCE_PATH), (
        f"C source file {SOURCE_PATH} is missing. You must create it."
    )


def test_posterior_result():
    assert os.path.isfile(RESULT_PATH), f"Result file {RESULT_PATH} is missing."
    with open(RESULT_PATH, "r") as f:
        content = f.read().strip()
    assert content == EXPECTED_ORIGINAL, (
        f"Content of {RESULT_PATH} is incorrect. Expected "
        f"'{EXPECTED_ORIGINAL}', got '{content}'."
    )


def test_c_source_contains_main():
    if os.path.isfile(SOURCE_PATH):
        with open(SOURCE_PATH, "r") as f:
            content = f.read()
        assert "main" in content, "The C source file does not appear to contain a main() function."


def posterior_expected(rows):
    s11 = sum(x1 * x1 for y, x1, x2 in rows) + 0.1
    s12 = sum(x1 * x2 for y, x1, x2 in rows)
    s22 = sum(x2 * x2 for y, x1, x2 in rows) + 0.1
    t1 = sum(x1 * y for y, x1, x2 in rows)
    t2 = sum(x2 * y for y, x1, x2 in rows)
    det = s11 * s22 - s12 * s12
    beta1 = (s22 * t1 - s12 * t2) / det
    beta2 = (s11 * t2 - s12 * t1) / det
    return f"beta1={beta1:.3f}, beta2={beta2:.3f}"


def write_rows(rows):
    with open(OBSERVATIONS_PATH, "w") as f:
        for y, x1, x2 in rows:
            f.write(f"{y:.6f};{x1:.6f};{x2:.6f}\n")


def run_and_check(executable, expected):
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)
    completed = subprocess.run(
        [executable], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert completed.returncode == 0, (
        f"Compiled program exited with status {completed.returncode}: {completed.stderr}"
    )
    assert os.path.isfile(RESULT_PATH), "The compiled program did not create posterior_result.txt."
    with open(RESULT_PATH, "r") as f:
        actual = f.read().strip()
    assert actual == expected, f"Expected result '{expected}', got '{actual}'."
    assert completed.stdout.strip() == expected, (
        f"Program stdout must be '{expected}', got '{completed.stdout.strip()}'."
    )


def test_compile_and_execute_on_derived_inputs():
    executable = f"/tmp/posterior_verify_{os.getpid()}"
    compile_result = subprocess.run(
        ["gcc", "-o", executable, SOURCE_PATH],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert compile_result.returncode == 0, f"posterior.c failed to compile: {compile_result.stderr}"
    assert os.path.isfile(executable) and os.access(executable, os.X_OK), (
        "gcc did not produce an executable program."
    )

    rng = random.SystemRandom()
    try:
        with open(OBSERVATIONS_PATH, "w") as f:
            f.write(ORIGINAL_DATA)
        run_and_check(executable, EXPECTED_ORIGINAL)

        for _ in range(3):
            rows = []
            for i in range(1, rng.randint(6, 10)):
                x1 = i + rng.randint(-200, 200) / 1000.0
                x2 = x1 + rng.randint(-60, 60) / 1000.0
                y = 4.1 * x1 + rng.randint(-300, 300) / 1000.0
                rows.append((y, x1, x2))
            write_rows(rows)
            # Re-read the exact decimal values supplied to the C program.
            supplied = []
            with open(OBSERVATIONS_PATH, "r") as f:
                for line in f:
                    y, x1, x2 = map(float, line.strip().split(";"))
                    supplied.append((y, x1, x2))
            run_and_check(executable, posterior_expected(supplied))
    finally:
        with open(OBSERVATIONS_PATH, "w") as f:
            f.write(ORIGINAL_DATA)
        if os.path.isfile(executable):
            subprocess.run(
                [executable], cwd="/home/user", text=True,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
            )
            os.remove(executable)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
