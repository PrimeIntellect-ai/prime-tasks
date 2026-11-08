#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import tempfile

import pytest

SOURCE = "/home/user/boot_corr.c"
EXECUTABLE = "/home/user/boot_corr"
DATA = "/home/user/data.csv"
RESULT = "/home/user/result.txt"


def test_c_source_exists():
    path = SOURCE
    assert os.path.isfile(path), f"C source file {path} does not exist."


def test_executable_exists():
    path = EXECUTABLE
    assert os.path.isfile(path), f"Compiled executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not a compiled ELF executable."


def test_result_txt_content():
    path = RESULT
    assert os.path.isfile(path), f"Result file {path} does not exist."

    with open(path, "r") as f:
        content = f.read().strip()

    assert "0.9984" in content, f"Expected '0.9984' in {path}, but found '{content}'."


def read_csv(path):
    rows = []
    with open(path, "r") as f:
        for line in f:
            if line.strip():
                a, b = line.strip().split(",")
                rows.append((float(a), float(b)))
    return rows


def bootstrap_mean(rows, iterations):
    seed = 42
    correlations = []
    count = len(rows)

    for _ in range(iterations):
        sample = []
        for _ in range(count):
            seed = (seed * 1103515245 + 12345) & 0x7fffffff
            sample.append(rows[seed % count])

        mean_x = sum(x for x, _ in sample) / count
        mean_y = sum(y for _, y in sample) / count
        covariance = sum((x - mean_x) * (y - mean_y) for x, y in sample)
        variance_x = sum((x - mean_x) ** 2 for x, _ in sample)
        variance_y = sum((y - mean_y) ** 2 for _, y in sample)
        denominator = math.sqrt(variance_x * variance_y)
        correlations.append(0.0 if denominator == 0.0 else covariance / denominator)

    return sum(correlations) / iterations


def run_and_check(program, csv_path, iterations):
    completed = subprocess.run(
        [program, csv_path, str(iterations)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"{program} failed with status {completed.returncode}: {completed.stderr}"
    )
    assert re.fullmatch(r"-?\d+\.\d{4}\n?", completed.stdout), (
        "Program output must contain only one number formatted to exactly four "
        f"decimal places; got {completed.stdout!r}."
    )

    expected = bootstrap_mean(read_csv(csv_path), iterations)
    expected_text = f"{expected:.4f}"
    assert completed.stdout.strip() == expected_text, (
        f"For {iterations} iterations, expected {expected_text}, "
        f"but got {completed.stdout.strip()!r}."
    )
    return completed.stdout.strip()


@pytest.fixture(scope="session")
def rebuilt_executable():
    output = os.path.join(tempfile.gettempdir(), "boot_corr_rebuilt_" + secrets.token_hex(8))
    completed = subprocess.run(
        ["gcc", "-O3", "-o", output, SOURCE, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, f"boot_corr.c does not compile: {completed.stderr}"
    yield output
    try:
        os.remove(output)
    except FileNotFoundError:
        pass


def test_required_run_matches_result(rebuilt_executable):
    expected_output = run_and_check(EXECUTABLE, DATA, 1000)
    run_and_check(rebuilt_executable, DATA, 1000)
    with open(RESULT, "r") as f:
        saved = f.read().strip()
    assert saved == expected_output, (
        f"{RESULT} does not contain the output produced by the required invocation."
    )


def test_bootstrap_on_unseen_inputs(rebuilt_executable):
    for row_count in (11, 17):
        path = os.path.join(tempfile.gettempdir(), "bootstrap_data_" + secrets.token_hex(8) + ".csv")
        with open(path, "w") as f:
            for i in range(row_count):
                x = i * 1.137 + secrets.randbelow(1000000) / 1000000.0
                y = ((i * i * 0.173) - i * 0.41 +
                     secrets.randbelow(4000000) / 1000000.0 - 2.0)
                f.write(f"{x:.9f},{y:.9f}\n")

        first_n = 7 + secrets.randbelow(9)
        second_n = first_n + 9 + secrets.randbelow(9)
        try:
            for program in (EXECUTABLE, rebuilt_executable):
                run_and_check(program, path, first_n)
                run_and_check(program, path, second_n)
        finally:
            os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
