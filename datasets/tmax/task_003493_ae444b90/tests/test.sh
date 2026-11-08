#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import struct
import subprocess


def parse_matrix_file(filepath):
    matrix = []
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(',')
            if len(parts) != 3:
                raise ValueError(f"Line does not have exactly 3 comma-separated values: {line}")
            matrix.append([float(p.strip()) for p in parts])
    return matrix


def calculate_truth(filepath):
    with open(filepath, 'rb') as f:
        raw = f.read()
    assert len(raw) % 12 == 0, "Raw data size is not a multiple of one record."

    records = []
    for offset in range(0, len(raw), 12):
        row = struct.unpack_from('fff', raw, offset)
        if any(value == -999.0 for value in row):
            continue
        records.append(row)

    assert len(records) >= 2, "Not enough valid records for sample covariance."
    means = [sum(row[j] for row in records) / len(records) for j in range(3)]
    denominator = len(records) - 1
    return [
        [
            sum((row[i] - means[i]) * (row[j] - means[j]) for row in records) / denominator
            for j in range(3)
        ]
        for i in range(3)
    ]


def test_c_source_file_exists():
    c_file = '/home/user/clean_covar.c'
    assert os.path.exists(c_file), f"The C source file {c_file} does not exist."
    assert os.path.isfile(c_file), f"The path {c_file} is not a file."


def test_program_compiles_and_runs():
    output = '/home/user/expected_covar.txt'
    if os.path.exists(output):
        os.remove(output)

    compile_result = subprocess.run(
        ['gcc', '/home/user/clean_covar.c', '-o', '/home/user/clean_covar', '-lm'],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"Compilation failed:\n{compile_result.stderr}"

    run_result = subprocess.run(
        ['/home/user/clean_covar'],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert run_result.returncode == 0, f"Program failed:\n{run_result.stderr}"


def test_output_file_exists():
    out_file = '/home/user/expected_covar.txt'
    assert os.path.exists(out_file), f"The output file {out_file} does not exist. Did you run your C program?"
    assert os.path.isfile(out_file), f"The path {out_file} is not a file."


def test_covariance_matrix_correctness():
    expected_file = '/home/user/expected_covar.txt'
    try:
        user_matrix = parse_matrix_file(expected_file)
    except Exception as e:
        assert False, f"Failed to parse {expected_file}: {e}"

    truth_matrix = calculate_truth('/home/user/raw_data.bin')
    assert len(user_matrix) == 3, f"Expected 3 rows in the covariance matrix, but got {len(user_matrix)}"

    tolerance = 0.0002
    for i in range(3):
        assert len(user_matrix[i]) == 3, f"Expected 3 columns in row {i+1}, but got {len(user_matrix[i])}"
        for j in range(3):
            user_val = user_matrix[i][j]
            truth_val = truth_matrix[i][j]
            assert math.isfinite(user_val), f"Non-finite value at row {i+1}, column {j+1}"
            diff = abs(user_val - truth_val)
            assert diff <= tolerance, (
                f"Value mismatch at row {i+1}, column {j+1}. "
                f"Expected {truth_val:.4f}, but got {user_val:.4f} "
                f"(difference {diff:.6f} > {tolerance})"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
