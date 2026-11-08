#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import subprocess

CPP_PATH = "/home/user/compute_cov.cpp"
EXE_PATH = "/home/user/compute_cov"
DATA_PATH = "/home/user/features.csv"
OUTPUT_PATH = "/home/user/cov_stats.txt"


def expected_stats(rows):
    n = len(rows)
    cols = len(rows[0])
    means = [sum(row[j] for row in rows) / n for j in range(cols)]
    variances = [
        sum((row[j] - means[j]) ** 2 for row in rows) / (n - 1)
        for j in range(cols)
    ]
    return sum(variances), variances[0]


def write_dataset(rows):
    with open(DATA_PATH, "w") as f:
        for row in rows:
            f.write(",".join(f"{value:.2f}" for value in row) + "\n")


def run_program():
    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        [EXE_PATH], capture_output=True, text=True, timeout=5
    )
    assert result.returncode == 0, (
        f"Program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(OUTPUT_PATH), (
        f"Output file {OUTPUT_PATH} does not exist after running the program."
    )
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file."
    with open(OUTPUT_PATH, "r") as f:
        return f.read()


def assert_computed_output(content, rows):
    match = re.fullmatch(
        r"Trace:\s*(-?(?:\d+\.\d{2}))\s*\n"
        r"TopLeft:\s*(-?(?:\d+\.\d{2}))\s*(?:\n)?",
        content,
    )
    assert match is not None, (
        "Output must contain exactly Trace and TopLeft values formatted to "
        f"two decimal places, but got:\n{content}"
    )
    expected_trace, expected_top_left = expected_stats(rows)
    actual_trace = float(match.group(1))
    actual_top_left = float(match.group(2))
    assert math.isclose(actual_trace, expected_trace, rel_tol=0, abs_tol=0.00501), (
        f"Expected trace {expected_trace:.2f}, got {actual_trace:.2f}."
    )
    assert math.isclose(actual_top_left, expected_top_left, rel_tol=0, abs_tol=0.00501), (
        f"Expected top-left {expected_top_left:.2f}, got {actual_top_left:.2f}."
    )


def test_submission_computes_covariance():
    # Preserve the original artifact assertions.
    assert os.path.exists(CPP_PATH), f"C++ source file {CPP_PATH} does not exist."
    assert os.path.isfile(CPP_PATH), f"{CPP_PATH} is not a file."

    assert os.path.exists(EXE_PATH), f"Executable {EXE_PATH} does not exist. Did you compile the code?"
    assert os.path.isfile(EXE_PATH), f"{EXE_PATH} is not a file."
    assert os.access(EXE_PATH, os.X_OK), f"{EXE_PATH} is not executable."

    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist. Did you run the program?"
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file."
    with open(OUTPUT_PATH, "r") as f:
        original_content = f.read()
    assert re.search(r"Trace:\s*70\.00", original_content) is not None, (
        f"Expected 'Trace: 70.00' in {OUTPUT_PATH}, but got:\n{original_content}"
    )
    assert re.search(r"TopLeft:\s*10\.00", original_content) is not None, (
        f"Expected 'TopLeft: 10.00' in {OUTPUT_PATH}, but got:\n{original_content}"
    )

    original_data = open(DATA_PATH, "rb").read()
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", CPP_PATH, "-o", EXE_PATH],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, (
        f"Submitted source did not compile.\nstdout:\n{compile_result.stdout}"
        f"\nstderr:\n{compile_result.stderr}"
    )
    assert os.path.isfile(EXE_PATH) and os.access(EXE_PATH, os.X_OK)

    original_rows = [
        [2.0, 4.0, 6.0],
        [4.0, 2.0, 8.0],
        [6.0, 10.0, 14.0],
        [8.0, 12.0, 16.0],
        [10.0, 14.0, 20.0],
    ]

    try:
        # Compile and execute the submitted source on the required dataset.
        content = run_program()
        assert_computed_output(content, original_rows)

        # Exercise the same executable on unpredictable valid 5x3 datasets.
        rng = random.SystemRandom()
        for _ in range(3):
            rows = [
                [rng.randint(-5000, 5000) / 100.0 for _ in range(3)]
                for _ in range(5)
            ]
            write_dataset(rows)
            content = run_program()
            assert_computed_output(content, rows)
    finally:
        with open(DATA_PATH, "wb") as f:
            f.write(original_data)
        try:
            subprocess.run([EXE_PATH], capture_output=True, timeout=5)
        except Exception:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
