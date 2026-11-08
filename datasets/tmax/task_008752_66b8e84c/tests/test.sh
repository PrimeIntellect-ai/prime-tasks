#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import csv
import subprocess
import tempfile
import pytest


def get_column(data, col_idx):
    return [row[col_idx] for row in data]


def compute_mean_std(values, ddof=0):
    n = len(values)
    mean = sum(values) / n
    variance = sum((x - mean) ** 2 for x in values) / (n - ddof)
    return mean, math.sqrt(variance)


@pytest.fixture(scope="module")
def truth_data():
    embeddings_path = "/home/user/data/embeddings.csv"
    assert os.path.exists(embeddings_path), f"Input file {embeddings_path} is missing."

    with open(embeddings_path, "r") as f:
        reader = csv.reader(f)
        data = [[float(val) for val in row] for row in reader]

    assert len(data) == 100, "Embeddings data should have exactly 100 rows."
    assert all(len(row) == 3 for row in data), "Each embeddings row must have exactly 3 columns."

    train_data = data[:80]
    test_data = data[80:]

    num_cols = len(data[0])
    train_means = []
    train_stds = []

    for c in range(num_cols):
        col_vals = get_column(train_data, c)
        m, s = compute_mean_std(col_vals, ddof=0)
        train_means.append(m)
        train_stds.append(s)

    train_norm = []
    for row in train_data:
        train_norm.append([(val - train_means[c]) / train_stds[c] for c, val in enumerate(row)])

    test_norm = []
    for row in test_data:
        test_norm.append([(val - train_means[c]) / train_stds[c] for c, val in enumerate(row)])

    test_f0 = get_column(test_norm, 0)
    mean_test_f0, std_test_f0 = compute_mean_std(test_f0, ddof=1)

    t_crit = 2.093
    n = len(test_f0)
    margin = t_crit * (std_test_f0 / math.sqrt(n))
    lower = mean_test_f0 - margin
    upper = mean_test_f0 + margin

    expected_ci_str = f"[{lower:.4f}, {upper:.4f}]"

    return {
        "train_norm": train_norm,
        "test_norm": test_norm,
        "ci_str": expected_ci_str
    }


@pytest.fixture(scope="module")
def pipeline_run(truth_data):
    source = "/home/user/pipeline.cpp"
    executable = "/home/user/pipeline"
    output_paths = ["/home/user/train_norm.csv", "/home/user/test_norm.csv"]

    assert os.path.isfile(source), f"Missing C++ source file {source}"
    assert os.path.isfile(executable), f"Missing compiled executable {executable}"
    assert os.access(executable, os.X_OK), f"{executable} is not executable"
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable} is not a compiled ELF executable"

    for path in output_paths:
        if os.path.exists(path):
            os.remove(path)

    result = subprocess.run([executable], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, \
        f"{executable} failed with exit code {result.returncode}: {result.stderr}"
    for path in output_paths:
        assert os.path.isfile(path), f"Running {executable} did not create {path}"
    submitted_outputs = {path: open(path, "rb").read() for path in output_paths}

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "pipeline")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", source, "-o", rebuilt],
            capture_output=True, text=True, timeout=60
        )
        assert compile_result.returncode == 0, \
            f"Failed to compile {source}: {compile_result.stderr}"

        for path in output_paths:
            os.remove(path)

        rebuilt_result = subprocess.run([rebuilt], capture_output=True, text=True, timeout=30)
        assert rebuilt_result.returncode == 0, \
            f"The program compiled from {source} failed: {rebuilt_result.stderr}"
        for path in output_paths:
            assert os.path.isfile(path), f"The program compiled from {source} did not create {path}"
            with open(path, "rb") as f:
                assert f.read() == submitted_outputs[path], \
                    f"{executable} does not produce the same {path} as the submitted C++ source"

    return True


def test_train_norm_correctness(truth_data, pipeline_run):
    train_file = "/home/user/train_norm.csv"
    assert os.path.exists(train_file), f"Missing {train_file}"

    with open(train_file, "r") as f:
        reader = csv.reader(f)
        actual_train = [[float(val) for val in row] for row in reader]

    expected_train = truth_data["train_norm"]
    assert len(actual_train) == len(expected_train), f"Expected {len(expected_train)} rows in {train_file}, got {len(actual_train)}"
    assert all(len(row) == 3 for row in actual_train), f"Every row in {train_file} must have exactly 3 columns"

    for i, (actual_row, expected_row) in enumerate(zip(actual_train, expected_train)):
        for j, (act, exp) in enumerate(zip(actual_row, expected_row)):
            assert math.isclose(act, exp, abs_tol=1e-5), f"Mismatch in {train_file} at row {i}, col {j}: expected {exp:.6f}, got {act:.6f}"


def test_test_norm_correctness(truth_data, pipeline_run):
    test_file = "/home/user/test_norm.csv"
    assert os.path.exists(test_file), f"Missing {test_file}"

    with open(test_file, "r") as f:
        reader = csv.reader(f)
        actual_test = [[float(val) for val in row] for row in reader]

    expected_test = truth_data["test_norm"]
    assert len(actual_test) == len(expected_test), f"Expected {len(expected_test)} rows in {test_file}, got {len(actual_test)}"
    assert all(len(row) == 3 for row in actual_test), f"Every row in {test_file} must have exactly 3 columns"

    for i, (actual_row, expected_row) in enumerate(zip(actual_test, expected_test)):
        for j, (act, exp) in enumerate(zip(actual_row, expected_row)):
            assert math.isclose(act, exp, abs_tol=1e-5), f"Mismatch in {test_file} at row {i}, col {j}: expected {exp:.6f}, got {act:.6f}"


def test_ci_output_correctness(truth_data, pipeline_run):
    ci_file = "/home/user/ci_output.txt"
    assert os.path.exists(ci_file), f"Missing {ci_file}"

    with open(ci_file, "r") as f:
        content = f.read().strip()

    expected_ci = truth_data["ci_str"]
    assert content == expected_ci, f"Mismatch in {ci_file} content. Expected '{expected_ci}', got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
