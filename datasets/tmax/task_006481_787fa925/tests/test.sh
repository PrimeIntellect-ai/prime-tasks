#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import math
import random
import subprocess
import tempfile
import pytest


def my_rand(seed):
    seed = (1103515245 * seed + 12345) % 2147483648
    return (seed / 2147483648.0), seed


def generate_true_data():
    width = 20
    height = 20
    steps = 50
    decay = 0.05
    seed = 42

    grid = [[100.0 for _ in range(width)] for _ in range(height)]
    data = []
    for t in range(steps):
        total = 0
        for i in range(height):
            for j in range(width):
                grid[i][j] = grid[i][j] * (1.0 - decay)
                rand_val, seed = my_rand(seed)
                noise = (rand_val - 0.5) * 2.0
                total += grid[i][j] + noise
        val = round(total / (width * height), 4)
        data.append((t, val))
    return data


def expected_lines():
    return [f"{t},{value:.4f}" for t, value in generate_true_data()]


def linear_regression(x, y):
    n = len(x)
    sum_x = sum(x)
    sum_y = sum(y)
    sum_xx = sum(xi * xi for xi in x)
    sum_xy = sum(xi * yi for xi, yi in zip(x, y))

    denominator = n * sum_xx - sum_x**2
    if denominator == 0:
        return 0
    return (n * sum_xy - sum_x * sum_y) / denominator


def compute_expected_results():
    data = generate_true_data()
    x = [d[0] for d in data]
    y = [math.log(d[1]) for d in data]
    k_est = -linear_regression(x, y)

    random.seed(42)
    k_boot = []
    n = len(data)
    for _ in range(1000):
        resample = [random.choice(data) for _ in range(n)]
        rx = [d[0] for d in resample]
        ry = [math.log(d[1]) for d in resample]
        k_boot.append(-linear_regression(rx, ry))

    k_boot.sort()
    return k_est, k_boot[25], k_boot[975]


def test_simulation_compiles_without_warnings_and_runs_correctly():
    source = "/home/user/sim.c"
    assert os.path.isfile(source), f"Missing source file: {source}"

    with tempfile.TemporaryDirectory() as tmpdir:
        executable = os.path.join(tmpdir, "sim")
        compilation = subprocess.run(
            ["gcc", "-Wall", "-Wextra", "-Werror", source, "-o", executable],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compilation.returncode == 0, (
            "sim.c did not compile without warnings:\n"
            + compilation.stdout
            + compilation.stderr
        )

        execution = subprocess.run(
            [executable],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert execution.returncode == 0, (
            f"Simulation exited with status {execution.returncode}:\n"
            + execution.stderr
        )

    lines = [line.strip() for line in execution.stdout.splitlines() if line.strip()]
    assert lines == expected_lines(), "Simulation output does not match the expected 50 steps"


def test_data_csv_exists_and_correct():
    file_path = "/home/user/data.csv"
    assert os.path.isfile(file_path), f"Missing file: {file_path}"

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    if lines and not lines[0][0].isdigit():
        lines = lines[1:]

    assert len(lines) == 50, f"Expected 50 data rows in data.csv, found {len(lines)}"
    expected = expected_lines()
    for i in range(50):
        assert lines[i] == expected[i], (
            f"Mismatch at step {i}: expected '{expected[i]}', got '{lines[i]}'"
        )


def test_results_json():
    file_path = "/home/user/results.json"
    assert os.path.isfile(file_path), f"Missing file: {file_path}"

    with open(file_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("results.json is not a valid JSON file.")

    for key in ["k_estimate", "ci_lower", "ci_upper"]:
        assert key in results, f"Missing key '{key}' in results.json"

    expected_k, expected_ci_lower, expected_ci_upper = compute_expected_results()

    assert abs(results["k_estimate"] - expected_k) <= 0.001, (
        f"k_estimate {results['k_estimate']} is not within 0.001 of expected {expected_k:.4f}"
    )
    assert abs(results["ci_lower"] - expected_ci_lower) <= 0.005, (
        f"ci_lower {results['ci_lower']} is not within 0.005 of expected {expected_ci_lower:.4f}"
    )
    assert abs(results["ci_upper"] - expected_ci_upper) <= 0.005, (
        f"ci_upper {results['ci_upper']} is not within 0.005 of expected {expected_ci_upper:.4f}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
