#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess

TRAINING_PATH = "/home/user/training_data.csv"
SOURCE_PATH = "/home/user/ridge_bootstrap.cpp"
RESULT_PATH = "/home/user/bootstrap_results.txt"
EXECUTABLE_PATH = "/tmp/ridge_bootstrap_submission"

EXPECTED_DATA = "x,y\n1.5,2.1\n2.0,3.9\n3.1,6.0\n4.5,8.8\n5.0,10.1"
EXPECTED_RESULT = "Mean: 1.9567\nStdDev: 0.0573"


def normalized_contents(path):
    with open(path, "r") as f:
        return f.read().strip().replace("\r\n", "\n")


def test_training_data_exists_and_correct():
    """Check that training_data.csv exists and has the correct contents."""
    assert os.path.exists(TRAINING_PATH), f"File {TRAINING_PATH} does not exist."
    content = normalized_contents(TRAINING_PATH)
    assert content == EXPECTED_DATA, f"Contents of {TRAINING_PATH} do not match the expected data."


def test_cpp_file_exists():
    """Check that the C++ source file exists."""
    assert os.path.exists(SOURCE_PATH), f"File {SOURCE_PATH} does not exist."
    assert os.path.isfile(SOURCE_PATH), f"File {SOURCE_PATH} is not a regular file."


def test_bootstrap_results_exists_and_correct():
    """Check that bootstrap_results.txt exists and has the exact expected output."""
    assert os.path.exists(RESULT_PATH), f"File {RESULT_PATH} does not exist."
    content = normalized_contents(RESULT_PATH)
    assert content == EXPECTED_RESULT, f"Contents of {RESULT_PATH} do not match the expected output. Got:\n{content}"


def oracle(rows):
    seed = 42
    weights = []
    n = len(rows)
    for _ in range(1000):
        sum_xy = 0.0
        sum_xx = 0.0
        for _ in range(n):
            seed = (1103515245 * seed + 12345) % 2147483648
            x, y = rows[seed % n]
            sum_xy += x * y
            sum_xx += x * x
        weights.append(sum_xy / (sum_xx + 2.0))

    mean = sum(weights) / len(weights)
    variance = sum((w - mean) ** 2 for w in weights) / (len(weights) - 1)
    return f"Mean: {mean:.4f}\nStdDev: {math.sqrt(variance):.4f}"


def safely_rounded(value):
    scaled = abs(value) * 10000.0
    return abs((scaled - math.floor(scaled)) - 0.5) > 0.15


def make_random_case(rng):
    while True:
        rows = [(rng.randint(5, 90) / 10.0, rng.randint(5, 180) / 10.0) for _ in range(5)]
        expected = oracle(rows)
        mean = float(expected.splitlines()[0].split(":", 1)[1])
        stddev = float(expected.splitlines()[1].split(":", 1)[1])
        if expected != EXPECTED_RESULT and safely_rounded(mean) and safely_rounded(stddev):
            return rows, expected


def write_dataset(rows):
    text = "x,y\n" + "\n".join(f"{x:.1f},{y:.1f}" for x, y in rows) + "\n"
    with open(TRAINING_PATH, "w") as f:
        f.write(text)


def run_submission(expected):
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)
    completed = subprocess.run(
        [EXECUTABLE_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"Compiled program exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(RESULT_PATH), "Compiled program did not create bootstrap_results.txt."
    actual = normalized_contents(RESULT_PATH)
    assert actual == expected, f"Compiled program produced incorrect output. Expected:\n{expected}\nGot:\n{actual}"


def test_compile_and_execute_implementation():
    compilation = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE_PATH, "-o", EXECUTABLE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compilation.returncode == 0, (
        f"ridge_bootstrap.cpp failed to compile.\nstdout:\n{compilation.stdout}\n"
        f"stderr:\n{compilation.stderr}"
    )
    assert os.path.isfile(EXECUTABLE_PATH) and os.access(EXECUTABLE_PATH, os.X_OK)

    try:
        with open(TRAINING_PATH, "w") as f:
            f.write(EXPECTED_DATA + "\n")
        run_submission(EXPECTED_RESULT)

        rng = secrets.SystemRandom()
        for _ in range(3):
            rows, expected = make_random_case(rng)
            write_dataset(rows)
            run_submission(expected)
    finally:
        with open(TRAINING_PATH, "w") as f:
            f.write(EXPECTED_DATA + "\n")
        with open(RESULT_PATH, "w") as f:
            f.write(EXPECTED_RESULT + "\n")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
