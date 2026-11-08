#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import subprocess
import tempfile

import pytest

DATA_PATH = "/home/user/data.csv"
RESULTS_PATH = "/home/user/results.txt"
SOURCE_PATH = "/home/user/analyze.c"


def expected_output(rows):
    x_values = [row[0] for row in rows]
    y_values = [row[1] for row in rows]
    n = len(rows)
    mean_x = sum(x_values) / n
    mean_y = sum(y_values) / n
    covariance = sum(
        (x - mean_x) * (y - mean_y) for x, y in rows
    ) / (n - 1)
    posterior_mean = (
        5.0 / 2.0 + n * mean_x / 3.0
    ) / (1.0 / 2.0 + n / 3.0)
    return f"Covariance: {covariance:.4f}\nPosterior Mean: {posterior_mean:.4f}\n"


def read_rows():
    rows = []
    with open(DATA_PATH, "r") as data_file:
        for line in data_file:
            parts = line.strip().split(",")
            if len(parts) == 2:
                rows.append((float(parts[0]), float(parts[1])))
    return rows


def assert_results_match(rows):
    assert os.path.isfile(RESULTS_PATH), f"Missing results file: {RESULTS_PATH}"
    with open(RESULTS_PATH, "r") as results_file:
        actual_output = results_file.read()

    expected_lines = [line.strip() for line in expected_output(rows).strip().split("\n")]
    actual_lines = [line.strip() for line in actual_output.strip().split("\n")]
    assert actual_lines == expected_lines, (
        "Results do not match expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_analyze_c_exists():
    """Test that the C program file was created."""
    assert os.path.isfile(SOURCE_PATH), f"Missing C program file: {SOURCE_PATH}"


def test_results_txt_matches_expected():
    """Test that results.txt exists and contains the correct computed values."""
    assert os.path.isfile(DATA_PATH), f"Missing data file: {DATA_PATH}"
    rows = read_rows()
    assert len(rows) > 1, "Not enough data points to compute covariance."
    assert_results_match(rows)


def test_c_program_compiles_and_computes_results():
    """Compile and execute the submitted C program on derived test datasets."""
    assert os.path.isfile(SOURCE_PATH), f"Missing C program file: {SOURCE_PATH}"

    with open(DATA_PATH, "rb") as data_file:
        original_data = data_file.read()

    fd, executable = tempfile.mkstemp(prefix="analyze-verifier-", dir="/tmp")
    os.close(fd)
    os.unlink(executable)

    subprocess.run(
        ["/usr/bin/gcc", "-std=c11", "-O2", SOURCE_PATH, "-lm", "-o", executable],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    def run_program():
        if os.path.exists(RESULTS_PATH):
            os.remove(RESULTS_PATH)
        subprocess.run(
            [executable],
            cwd="/home/user",
            check=True,
            timeout=10,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            preexec_fn=demote,
        )

    try:
        for seed in (73129, 99173):
            rng = random.Random(seed)
            generated = []
            for i in range(100):
                x = round(rng.uniform(-20.0, 30.0), 6)
                y = round(0.37 * x + rng.uniform(-8.0, 8.0) + i * 0.013, 6)
                generated.append((x, y))

            with open(DATA_PATH, "w") as data_file:
                for x, y in generated:
                    data_file.write(f"{x:.6f},{y:.6f}\n")

            run_program()
            assert_results_match(generated)
    finally:
        with open(DATA_PATH, "wb") as data_file:
            data_file.write(original_data)
        try:
            run_program()
        finally:
            if os.path.exists(executable):
                os.remove(executable)

    original_rows = read_rows()
    assert len(original_rows) > 1, "Not enough original data points."
    assert_results_match(original_rows)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
