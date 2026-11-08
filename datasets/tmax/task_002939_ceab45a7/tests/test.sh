#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import stat
import subprocess

SENSOR_DIR = '/home/user/sensor'
INPUT_PATH = '/home/user/sensor_data.csv'
OUTPUT_PATH = '/home/user/cleaned_data.csv'


def compute_expected_cleaned_data(input_path=INPUT_PATH):
    assert os.path.exists(input_path), f"Input file {input_path} is missing."

    with open(input_path, 'r') as f:
        reader = csv.DictReader(f)
        data = [(float(row['X']), float(row['Y'])) for row in reader]

    N = len(data)
    assert N > 0, "Input data is empty."

    sum_x = sum(x for x, y in data)
    sum_y = sum(y for x, y in data)
    sum_xy = sum(x * y for x, y in data)
    sum_x2 = sum(x**2 for x, y in data)

    denominator = N * sum_x2 - sum_x**2
    assert denominator != 0, "Input data cannot be fitted."
    m = (N * sum_xy - sum_x * sum_y) / denominator
    c = (sum_y - m * sum_x) / N

    residuals = [y - (m * x + c) for x, y in data]
    variance = sum(r**2 for r in residuals) / N
    std_dev = math.sqrt(variance)

    cleaned = []
    for i, (x, y) in enumerate(data):
        if abs(residuals[i]) <= 2 * std_dev:
            cleaned.append((x, y))

    return cleaned


def assert_cleaned_file(expected_data):
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."
    with open(OUTPUT_PATH, 'r') as f:
        lines = f.read().splitlines()

    assert len(lines) > 0, f"File {OUTPUT_PATH} is empty."
    assert lines[0] == "X,Y", f"Header in {OUTPUT_PATH} is incorrect. Expected 'X,Y', got '{lines[0]}'."

    actual_data = lines[1:]
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} data rows, got {len(actual_data)}."
    for i, (expected_x, expected_y) in enumerate(expected_data):
        expected_line = f"{expected_x:.1f},{expected_y:.1f}"
        assert actual_data[i] == expected_line, f"Row {i+1} mismatch. Expected '{expected_line}', got '{actual_data[i]}'."


def run_cleaner():
    result = subprocess.run(
        ['go', 'run', 'clean.go'],
        cwd=SENSOR_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f"go run clean.go failed:\n{result.stdout}"


def test_go_implementation_and_fresh_benchmark():
    clean_go = os.path.join(SENSOR_DIR, 'clean.go')
    clean_test_go = os.path.join(SENSOR_DIR, 'clean_test.go')
    go_mod = os.path.join(SENSOR_DIR, 'go.mod')

    for path in (clean_go, clean_test_go, go_mod):
        assert os.path.exists(path), f"Required file {path} is missing."
        assert stat.S_ISREG(os.stat(path).st_mode), f"Required path {path} is not a regular file."

    with open(INPUT_PATH, 'rb') as f:
        original_input = f.read()

    rng = random.SystemRandom()
    slope = rng.choice([1.7, 2.3, 3.1, 4.3, 5.2])
    intercept = rng.choice([-8.4, -3.2, 1.6, 6.7, 11.3])
    outlier_a, outlier_b = rng.sample(range(2, 19), 2)
    rows = []
    for i in range(21):
        x = float(i)
        noise = rng.choice([-0.2, -0.1, 0.0, 0.1, 0.2])
        y = round(slope * x + intercept + noise, 1)
        if i == outlier_a:
            y = round(y + rng.choice([90.0, 110.0, 130.0]), 1)
        elif i == outlier_b:
            y = round(y - rng.choice([85.0, 105.0, 125.0]), 1)
        rows.append((x, y))

    challenge = 'X,Y\n' + ''.join(f'{x:.1f},{y:.1f}\n' for x, y in rows)
    try:
        with open(INPUT_PATH, 'w') as f:
            f.write(challenge)
        expected_challenge = compute_expected_cleaned_data(INPUT_PATH)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        run_cleaner()
        assert_cleaned_file(expected_challenge)
    finally:
        with open(INPUT_PATH, 'wb') as f:
            f.write(original_input)

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    run_cleaner()
    with open(INPUT_PATH, 'rb') as f:
        assert f.read() == original_input, "clean.go modified the input dataset."

    bench = subprocess.run(
        ['go', 'test', '-run=^$', '-bench=^BenchmarkInference$', '-benchtime=100ms', '-count=1'],
        cwd=SENSOR_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert bench.returncode == 0, f"Go benchmark failed:\n{bench.stdout}"
    genuine_line = re.compile(r'^BenchmarkInference(?:-\d+)?\s+\d+\s+[0-9.]+\s+ns/op(?:\s|$)', re.MULTILINE)
    assert genuine_line.search(bench.stdout), f"A runnable BenchmarkInference result was not produced:\n{bench.stdout}"


def test_cleaned_data_csv():
    output_path = '/home/user/cleaned_data.csv'
    assert os.path.exists(output_path), f"Output file {output_path} is missing."

    expected_data = compute_expected_cleaned_data()

    with open(output_path, 'r') as f:
        lines = f.read().splitlines()

    assert len(lines) > 0, f"File {output_path} is empty."
    assert lines[0] == "X,Y", f"Header in {output_path} is incorrect. Expected 'X,Y', got '{lines[0]}'."

    actual_data = lines[1:]
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} data rows, got {len(actual_data)}."

    for i, (expected_x, expected_y) in enumerate(expected_data):
        expected_line = f"{expected_x:.1f},{expected_y:.1f}"
        assert actual_data[i] == expected_line, f"Row {i+1} mismatch. Expected '{expected_line}', got '{actual_data[i]}'."


def test_benchmark_output():
    bench_path = '/home/user/benchmark.txt'
    assert os.path.exists(bench_path), f"Benchmark output file {bench_path} is missing."

    with open(bench_path, 'r') as f:
        content = f.read()

    assert 'BenchmarkInference' in content, f"'BenchmarkInference' not found in {bench_path}."
    assert 'ns/op' in content, f"'ns/op' not found in {bench_path}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
