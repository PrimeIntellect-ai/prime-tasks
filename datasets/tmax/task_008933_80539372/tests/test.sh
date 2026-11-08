#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import stat
import subprocess
from pathlib import Path

import pytest

PROJECT = Path("/home/user/sensor_analysis")
SOURCE = PROJECT / "src/main.rs"
DATA = PROJECT / "data.csv"
RESULTS = PROJECT / "results.txt"
BINARY = PROJECT / "target/debug/sensor_analysis"

ORIGINAL_DATA = """id,sensor_a,sensor_b
1,10.5,20.1
2,NA,19.5
3,12.0,22.0
4,-9999.0,25.0
5,11.0,21.0
6,10.0,19.0
7,13.5,24.5
8,invalid,12.1
9,15.1,-9999.0
10,14.0,25.5
"""

ORIGINAL_EXPECTED = (
    "Valid rows: 6\n"
    "Mean A: 11.833\n"
    "Mean B: 22.017\n"
    "Correlation: 0.996"
)


def run_program():
    if RESULTS.exists() or RESULTS.is_symlink():
        RESULTS.unlink()

    completed = subprocess.run(
        [str(BINARY)],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        "The built Rust program failed.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )
    assert RESULTS.exists(), (
        f"File {RESULTS} does not exist. Did the Rust program run and create it?"
    )


def expected_output(points):
    count = len(points)
    mean_a = sum(a for a, _ in points) / count
    mean_b = sum(b for _, b in points) / count
    numerator = sum((a - mean_a) * (b - mean_b) for a, b in points)
    sum_sq_a = sum((a - mean_a) ** 2 for a, _ in points)
    sum_sq_b = sum((b - mean_b) ** 2 for _, b in points)
    correlation = numerator / math.sqrt(sum_sq_a * sum_sq_b)
    return (
        f"Valid rows: {count}\n"
        f"Mean A: {mean_a:.3f}\n"
        f"Mean B: {mean_b:.3f}\n"
        f"Correlation: {correlation:.3f}"
    )


@pytest.fixture(scope="session", autouse=True)
def build_and_run_original():
    assert SOURCE.exists(), f"Required Rust source file {SOURCE} does not exist"
    metadata = SOURCE.lstat()
    assert stat.S_ISREG(metadata.st_mode), f"{SOURCE} must be a regular source file"
    assert SOURCE.stat().st_size > 0, f"{SOURCE} is empty"

    DATA.write_text(ORIGINAL_DATA)
    build = subprocess.run(
        ["cargo", "build", "--quiet"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert build.returncode == 0, (
        "The Rust project did not build successfully.\n"
        f"stdout:\n{build.stdout}\n"
        f"stderr:\n{build.stderr}"
    )
    assert BINARY.is_file(), f"Cargo did not produce the expected executable {BINARY}"
    run_program()
    yield


def test_results_file_exists():
    """Check if the results.txt file was created."""
    assert os.path.exists(RESULTS), (
        f"File {RESULTS} does not exist. Did the Rust program run and create it?"
    )


def test_results_content():
    """Verify the computed statistics in results.txt."""
    if not os.path.exists(RESULTS):
        pytest.fail(f"File {RESULTS} does not exist.")

    content = RESULTS.read_text().strip()
    assert content == ORIGINAL_EXPECTED, (
        f"The content of {RESULTS} is incorrect.\n"
        f"Expected:\n{ORIGINAL_EXPECTED}\n\n"
        f"Got:\n{content}"
    )


def test_program_handles_unseen_data_and_corrupt_rows():
    rng = secrets.SystemRandom()

    try:
        for case_number in range(3):
            count = 6 + rng.randrange(5)
            base_a = rng.randrange(-20000, 20001) / 137.0
            base_b = rng.randrange(-15000, 15001) / 113.0
            points = []

            for i in range(count):
                a = base_a + i * 1.137 + rng.randrange(-300, 301) / 997.0
                b = base_b + 1.73 * a + ((i % 3) - 1) * 0.419 + rng.randrange(-200, 201) / 991.0
                points.append((a, b))

            rows = [
                f"{i + 1},{a:.9f},{b:.9f}"
                for i, (a, b) in enumerate(points)
            ]
            next_id = count + 1
            rows.extend([
                f"{next_id},,99999.25",
                f"{next_id + 1},NA,-88888.5",
                f"{next_id + 2},not-a-number,77777.75",
                f"{next_id + 3},88888.25,",
                f"{next_id + 4},-77777.5,NA",
                f"{next_id + 5},66666.5,broken",
                f"{next_id + 6},-9999.0,55555.5",
                f"{next_id + 7},44444.5,-9999.0",
            ])
            rng.shuffle(rows)
            DATA.write_text("id,sensor_a,sensor_b\n" + "\n".join(rows) + "\n")

            # Compute expectations from the exact decimal values written to CSV.
            written_points = [(float(f"{a:.9f}"), float(f"{b:.9f}")) for a, b in points]
            expected = expected_output(written_points)
            run_program()
            actual = RESULTS.read_text().strip()
            assert actual == expected, (
                f"Incorrect output for unseen test dataset {case_number + 1}.\n"
                f"Expected:\n{expected}\n\nGot:\n{actual}"
            )
    finally:
        DATA.write_text(ORIGINAL_DATA)
        run_program()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
