#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import random
import subprocess
import pytest


def compute_pearson_correlation(csv_path):
    with open(csv_path, 'r') as f:
        lines = f.read().strip().split('\n')

    header = lines[0].split(',')
    latency_idx = header.index('latency_ms')
    accuracy_idx = header.index('accuracy')

    x = []
    y = []
    for line in lines[1:]:
        if not line.strip():
            continue
        parts = line.split(',')
        x.append(float(parts[latency_idx]))
        y.append(float(parts[accuracy_idx]))

    n = len(x)
    sum_x = sum(x)
    sum_y = sum(y)
    sum_x2 = sum(xi ** 2 for xi in x)
    sum_y2 = sum(yi ** 2 for yi in y)
    sum_xy = sum(xi * yi for xi, yi in zip(x, y))

    numerator = n * sum_xy - sum_x * sum_y
    denominator = math.sqrt((n * sum_x2 - sum_x ** 2) * (n * sum_y2 - sum_y ** 2))

    if denominator == 0:
        return 0.0
    return numerator / denominator


def test_analyze_c_exists():
    """Test that the C source file was created."""
    file_path = "/home/user/analyze.c"
    assert os.path.exists(file_path), f"Missing required file: {file_path}"
    assert os.path.isfile(file_path), f"Path exists but is not a file: {file_path}"


def test_correlation_result_exists():
    """Test that the output file was created."""
    file_path = "/home/user/correlation_result.txt"
    assert os.path.exists(file_path), f"Missing required file: {file_path}"
    assert os.path.isfile(file_path), f"Path exists but is not a file: {file_path}"


def test_correlation_result_content():
    """Test that the output file contains the correct correlation coefficient."""
    csv_path = "/home/user/experiments.csv"
    assert os.path.exists(csv_path), f"Missing required file: {csv_path}"

    expected_r = compute_pearson_correlation(csv_path)
    expected_output = f"Correlation: {expected_r:.4f}"

    result_path = "/home/user/correlation_result.txt"
    with open(result_path, "r") as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, (
        f"Incorrect correlation result in {result_path}. "
        f"Expected: '{expected_output}', Got: '{actual_output}'"
    )


def test_source_compiles_and_computes_from_csv():
    source_path = "/home/user/analyze.c"
    csv_path = "/home/user/experiments.csv"
    result_path = "/home/user/correlation_result.txt"
    binary_path = "/tmp/analyze_submission"

    subprocess.run(
        ["gcc", source_path, "-o", binary_path, "-lm"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert os.path.isfile(binary_path), "gcc did not produce the requested program"

    with open(csv_path, "rb") as f:
        original_csv = f.read()
    original_result = None
    if os.path.isfile(result_path):
        with open(result_path, "rb") as f:
            original_result = f.read()

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    generated_cases = []
    for case_number in range(4):
        rows = ["experiment_id,learning_rate,batch_size,latency_ms,accuracy"]
        count = rng.randint(5, 10)
        for i in range(count):
            latency = rng.uniform(2.0, 250.0)
            accuracy = rng.uniform(0.25, 0.99)
            rows.append(
                f"{i + 1},{rng.uniform(0.00001, 0.1):.10f},{16 * (i + 1)},"
                f"{latency:.10f},{accuracy:.10f}"
            )
        generated_cases.append("\n".join(rows) + "\n")

    try:
        cases = [original_csv.decode("utf-8")] + generated_cases
        for csv_content in cases:
            with open(csv_path, "w") as f:
                f.write(csv_content)

            if os.path.lexists(result_path):
                os.unlink(result_path)

            subprocess.run(
                [binary_path],
                check=True,
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )

            assert os.path.isfile(result_path), (
                "The compiled program did not create /home/user/correlation_result.txt"
            )
            expected = f"Correlation: {compute_pearson_correlation(csv_path):.4f}"
            with open(result_path, "r") as f:
                actual = f.read().strip()
            assert actual == expected, (
                "The compiled analyze.c program did not compute the correlation "
                f"for the supplied CSV. Expected '{expected}', got '{actual}'"
            )
    finally:
        with open(csv_path, "wb") as f:
            f.write(original_csv)
        if os.path.lexists(result_path):
            os.unlink(result_path)
        if original_result is not None:
            with open(result_path, "wb") as f:
                f.write(original_result)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
