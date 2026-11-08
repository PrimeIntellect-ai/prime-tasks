#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess

import pytest


def compute_expected_mse(csv_path, iterations=1000, sample_size=50, seed=42):
    dataset = []
    with open(csv_path, "r") as f:
        reader = csv.reader(f)
        next(reader)
        for row in reader:
            if not row:
                continue
            dataset.append((float(row[0]), float(row[1])))

    N = len(dataset)
    state = seed
    total_mse = 0.0
    for _ in range(iterations):
        sample_mse = 0.0
        for _ in range(sample_size):
            state = (1103515245 * state + 12345) % 2147483648
            idx = state % N
            x, true_y = dataset[idx]
            pred_y = 2.5 + 1.2 * x - 0.3 * (x ** 2)
            sample_mse += (pred_y - true_y) ** 2
        total_mse += sample_mse / sample_size
    return f"{total_mse / iterations:.4f}"


def run_evaluator(executable, csv_path, iterations, sample_size, seed, output_path):
    if os.path.exists(output_path):
        os.remove(output_path)
    subprocess.run(
        [executable, csv_path, str(iterations), str(sample_size), str(seed), output_path],
        check=True,
        timeout=20,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert os.path.isfile(output_path), f"Evaluator did not create {output_path}"
    with open(output_path, "r") as f:
        content = f.read()

    match = re.fullmatch(
        r"Avg_MSE: (-?\d+\.\d{4})\nAvg_Time_us: ([^\s]+)\n?",
        content,
    )
    assert match is not None, f"Output has the wrong format: {content!r}"
    actual_mse = match.group(1)
    expected_mse = compute_expected_mse(csv_path, iterations, sample_size, seed)
    assert actual_mse == expected_mse, (
        f"Expected Avg_MSE {expected_mse}, got {actual_mse} for "
        f"iterations={iterations}, sample_size={sample_size}, seed={seed}"
    )
    try:
        elapsed = float(match.group(2))
    except ValueError:
        pytest.fail(f"Avg_Time_us is not numeric: {match.group(2)!r}")
    assert math.isfinite(elapsed) and elapsed >= 0, f"Invalid Avg_Time_us: {elapsed}"
    return elapsed


@pytest.fixture(scope="session")
def rebuilt_evaluator():
    output = f"/tmp/evaluator_rebuilt_{os.getpid()}"
    subprocess.run(
        ["g++", "-O3", "-std=c++17", "-o", output, "/home/user/evaluator.cpp"],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    return output


def test_evaluator_cpp_exists():
    assert os.path.exists("/home/user/evaluator.cpp"), "/home/user/evaluator.cpp does not exist."


def test_evaluator_binary_exists():
    assert os.path.exists("/home/user/evaluator"), "/home/user/evaluator does not exist."
    assert os.access("/home/user/evaluator", os.X_OK), "/home/user/evaluator is not executable."
    with open("/home/user/evaluator", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/evaluator is not a compiled executable."


def test_results_file_exists():
    assert os.path.exists("/home/user/results.txt"), "/home/user/results.txt does not exist."


def test_results_contents():
    csv_path = "/home/user/dataset.csv"
    assert os.path.exists(csv_path), f"{csv_path} is missing."

    subprocess.run(
        ["/home/user/evaluator", csv_path, "1000", "50", "42", "/home/user/results.txt"],
        check=True,
        timeout=20,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    expected_mse = compute_expected_mse(csv_path)
    with open("/home/user/results.txt", "r") as f:
        content = f.read()

    mse_match = re.search(r"Avg_MSE:\s*([\d\.]+)", content)
    assert mse_match is not None, "Avg_MSE not found in /home/user/results.txt"
    actual_mse = mse_match.group(1)
    assert actual_mse == expected_mse, f"Expected Avg_MSE to be {expected_mse}, got {actual_mse}"

    time_match = re.search(r"Avg_Time_us:\s*([\d\.]+)", content)
    assert time_match is not None, "Avg_Time_us not found in /home/user/results.txt"
    actual_time = float(time_match.group(1))
    assert actual_time >= 0, f"Expected Avg_Time_us to be >= 0, got {actual_time}"


def test_source_uses_required_clock():
    with open("/home/user/evaluator.cpp", "r") as f:
        source = f.read()
    assert "high_resolution_clock" in source, "Source does not use std::chrono::high_resolution_clock."


def test_submitted_and_rebuilt_programs_on_derived_cases(tmp_path, rebuilt_evaluator):
    datasets = [
        [(-3.25, 7.1), (-0.2, -4.0), (0.75, 8.25), (4.5, -2.2)],
        [(-7.0, 1.0), (-1.1, 3.3), (0.0, 2.5), (2.2, 0.0), (9.0, -8.5), (1.3, 4.4), (5.1, 6.2)],
    ]
    cases = [(1, 1, 0), (7, 13, 987654321), (19, 31, 2147483647)]

    for dataset_number, rows in enumerate(datasets):
        csv_path = tmp_path / f"input_{dataset_number}.csv"
        with open(csv_path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["x", "true_y"])
            writer.writerows(rows)

        for executable_number, executable in enumerate(["/home/user/evaluator", rebuilt_evaluator]):
            for case_number, (iterations, sample_size, seed) in enumerate(cases):
                output = tmp_path / f"out_{dataset_number}_{executable_number}_{case_number}.txt"
                run_evaluator(
                    executable,
                    str(csv_path),
                    iterations,
                    sample_size,
                    seed,
                    str(output),
                )


def test_benchmark_is_actually_recorded(tmp_path, rebuilt_evaluator):
    csv_path = tmp_path / "benchmark.csv"
    with open(csv_path, "w") as f:
        f.write("x,true_y\n-2.75,4.1\n0.125,-1.3\n3.8,9.2\n6.1,-4.7\n")

    for number, executable in enumerate(["/home/user/evaluator", rebuilt_evaluator]):
        elapsed = run_evaluator(
            executable,
            str(csv_path),
            2,
            300000,
            13579,
            str(tmp_path / f"benchmark_{number}.txt"),
        )
        assert elapsed > 0, "A substantial inference run must report a positive measured time."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
