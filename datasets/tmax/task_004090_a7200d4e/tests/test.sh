#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest


def read_csv(path):
    with open(path, 'r') as f:
        return [line.strip().split(',') for line in f if line.strip()]


def parse_float(val):
    if val == "NaN":
        return None
    return float(val)


def is_close(a, b, atol=1e-3):
    return abs(a - b) <= atol


@pytest.fixture(scope="module", autouse=True)
def compile_and_run_submission():
    source_path = "/home/user/analyze.cpp"
    binary_path = "/home/user/analyze"
    output_paths = ["/home/user/cov.csv", "/home/user/predictions.csv"]

    assert os.path.isfile(source_path), "C++ source code /home/user/analyze.cpp is missing."

    if os.path.lexists(binary_path):
        os.remove(binary_path)
    for path in output_paths:
        if os.path.lexists(path):
            os.remove(path)

    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", "-I/usr/include/eigen3", source_path, "-o", binary_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"Failed to compile analyze.cpp:\n{result.stderr}"
    assert os.path.isfile(binary_path), "Compilation did not create /home/user/analyze."
    assert os.access(binary_path, os.X_OK), "/home/user/analyze is not executable."

    result = subprocess.run(
        [binary_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"/home/user/analyze failed:\n{result.stderr}"


@pytest.fixture(scope="module")
def expected_data():
    data_path = "/home/user/data.csv"
    weights_path = "/home/user/weights.csv"

    assert os.path.exists(data_path), f"Missing {data_path}"
    assert os.path.exists(weights_path), f"Missing {weights_path}"

    data = read_csv(data_path)
    cols = len(data[0])
    rows = len(data)

    parsed_data = [[parse_float(val) for val in row] for row in data]

    means = []
    for c in range(cols):
        valid_vals = [parsed_data[r][c] for r in range(rows) if parsed_data[r][c] is not None]
        means.append(sum(valid_vals) / len(valid_vals))

    imputed_data = []
    for r in range(rows):
        row_vals = []
        for c in range(cols):
            val = parsed_data[r][c]
            row_vals.append(val if val is not None else means[c])
        imputed_data.append(row_vals)

    weights_raw = read_csv(weights_path)
    weights = [float(row[0]) for row in weights_raw]

    expected_preds = []
    for row in imputed_data:
        pred = sum(row[i] * weights[i] for i in range(cols))
        expected_preds.append(pred)

    expected_cov = []
    for i in range(cols):
        cov_row = []
        for j in range(cols):
            cov = sum((imputed_data[r][i] - means[i]) * (imputed_data[r][j] - means[j]) for r in range(rows)) / rows
            cov_row.append(cov)
        expected_cov.append(cov_row)

    return expected_preds, expected_cov


def test_source_code_exists():
    assert os.path.isfile("/home/user/analyze.cpp"), "C++ source code /home/user/analyze.cpp is missing."


def test_executable_exists():
    assert os.path.isfile("/home/user/analyze"), "Compiled executable /home/user/analyze is missing."
    assert os.access("/home/user/analyze", os.X_OK), "/home/user/analyze is not executable."


def test_predictions_output(expected_data):
    expected_preds, _ = expected_data
    output_path = "/home/user/predictions.csv"

    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

    preds_out = read_csv(output_path)
    assert len(preds_out) == len(expected_preds), f"Expected {len(expected_preds)} rows in predictions.csv, got {len(preds_out)}."

    for i, row in enumerate(preds_out):
        assert len(row) == 1, f"Expected 1 column in predictions.csv row {i+1}, got {len(row)}."
        val = float(row[0])
        expected_val = expected_preds[i]
        assert is_close(val, expected_val, atol=1e-3), f"Prediction at row {i+1} mismatch: expected {expected_val}, got {val}."


def test_covariance_output(expected_data):
    _, expected_cov = expected_data
    output_path = "/home/user/cov.csv"

    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

    cov_out = read_csv(output_path)
    assert len(cov_out) == len(expected_cov), f"Expected {len(expected_cov)} rows in cov.csv, got {len(cov_out)}."

    for i, row in enumerate(cov_out):
        assert len(row) == len(expected_cov[i]), f"Expected {len(expected_cov[i])} columns in cov.csv row {i+1}, got {len(row)}."
        for j, val_str in enumerate(row):
            val = float(val_str)
            expected_val = expected_cov[i][j]
            assert is_close(val, expected_val, atol=1e-3), f"Covariance at ({i+1}, {j+1}) mismatch: expected {expected_val}, got {val}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
