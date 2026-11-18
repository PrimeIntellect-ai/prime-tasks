#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import subprocess

import numpy as np


def test_eigen_extracted():
    """Test that the Eigen library was downloaded and extracted."""
    eigen_path = '/home/user/eigen/eigen-3.4.0/Eigen'
    assert os.path.isdir(eigen_path), f"Eigen library directory {eigen_path} not found. Did you extract it correctly?"


def test_cpp_file_exists():
    """Test that the C++ source file was created."""
    cpp_file = '/home/user/etl_pipeline.cpp'
    assert os.path.isfile(cpp_file), f"C++ source file {cpp_file} is missing."


def test_processed_data_exists():
    """Test that the output CSV file was created."""
    output_file = '/home/user/processed_data.csv'
    assert os.path.isfile(output_file), f"Output file {output_file} is missing. Did the C++ program run successfully?"


def test_processed_data_format():
    """Test that the output CSV has the correct dimensions and data types."""
    output_file = '/home/user/processed_data.csv'
    if not os.path.isfile(output_file):
        return

    with open(output_file, 'r') as f:
        rows = list(csv.reader(f))

    assert len(rows) == 7, f"Expected 7 rows in the output data, but got {len(rows)}."
    for i, row in enumerate(rows):
        assert len(row) == 2, f"Expected 2 columns (top 2 principal components) in row {i+1}, but got {len(row)}."
        for j, val in enumerate(row):
            try:
                float(val)
            except ValueError:
                assert False, f"Value '{val}' in row {i+1}, column {j+1} is not a valid float."


def test_processed_data_mean_centered():
    """Projected PCA data should be mean-centered."""
    output_file = '/home/user/processed_data.csv'
    if not os.path.isfile(output_file):
        return

    with open(output_file, 'r') as f:
        rows = list(csv.reader(f))

    col1 = [float(row[0]) for row in rows]
    col2 = [float(row[1]) for row in rows]
    mean1 = sum(col1) / len(col1)
    mean2 = sum(col2) / len(col2)
    assert abs(mean1) < 1e-3, f"Expected column 1 mean to be close to 0, got {mean1}"
    assert abs(mean2) < 1e-3, f"Expected column 2 mean to be close to 0, got {mean2}"


def _reference_pca(raw):
    data = raw.copy()
    for col in range(data.shape[1]):
        valid_mean = np.nanmean(data[:, col])
        data[np.isnan(data[:, col]), col] = valid_mean

    means = data.mean(axis=0)
    stds = np.sqrt(((data - means) ** 2).mean(axis=0))
    data = np.minimum(np.maximum(data, means - 2.0 * stds), means + 2.0 * stds)

    centered = data - data.mean(axis=0)
    covariance = centered.T @ centered / data.shape[0]
    eigenvalues, eigenvectors = np.linalg.eigh(covariance)
    return centered @ eigenvectors[:, np.argsort(eigenvalues)[-2:]]


def _write_input(path, matrix):
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        for row in matrix:
            writer.writerow(['NaN' if np.isnan(v) else format(float(v), '.12g') for v in row])


def _read_strict_output(path, expected_rows):
    assert os.path.isfile(path), 'The compiled program did not create /home/user/processed_data.csv'
    with open(path, newline='') as f:
        rows = list(csv.reader(f))
    assert len(rows) == expected_rows, f'Expected {expected_rows} output rows, got {len(rows)}'
    decimal = re.compile(r'^[-+]?\d+\.\d{6}$')
    result = []
    for i, row in enumerate(rows):
        assert len(row) == 2, f'Expected 2 output columns in row {i + 1}, got {len(row)}'
        assert all(decimal.fullmatch(v) for v in row), f'Row {i + 1} is not written with exactly 6 decimal places: {row}'
        values = [float(v) for v in row]
        assert all(np.isfinite(values)), f'Row {i + 1} contains a non-finite value'
        result.append(values)
    return np.asarray(result, dtype=float)


def test_compile_and_execute_pipeline_on_derived_inputs():
    source = '/home/user/etl_pipeline.cpp'
    eigen_root = '/home/user/eigen/eigen-3.4.0'
    binary = '/tmp/etl_pipeline_verified'
    raw_path = '/home/user/raw_sensors.csv'
    output_path = '/home/user/processed_data.csv'

    with open(source, encoding='utf-8', errors='replace') as f:
        source_text = f.read()
    assert source_text.strip(), 'The C++ source file is empty.'
    assert re.search(r'#\s*include\s*[<\"][^>\"]*Eigen[^>\"]*[>\"]', source_text, re.IGNORECASE), \
        'The C++ implementation does not include the requested Eigen library.'

    compile_result = subprocess.run(
        ['g++', '-std=c++17', '-O3', '-I', eigen_root, source, '-o', binary],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90
    )
    assert compile_result.returncode == 0, 'etl_pipeline.cpp did not compile:\n' + compile_result.stdout
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), 'Compilation did not produce an executable.'

    raw_backup = open(raw_path, 'rb').read()
    output_existed = os.path.exists(output_path)
    output_backup = open(output_path, 'rb').read() if output_existed else None

    try:
        seed = int.from_bytes(os.urandom(8), 'little')
        rng = np.random.default_rng(seed)
        cases = []
        for n in (9, 12):
            latent = rng.normal(size=(n, 3))
            raw = np.column_stack([
                3.0 * latent[:, 0] + 0.2 * latent[:, 2] + 1.5,
                -1.7 * latent[:, 0] + 0.5 * latent[:, 1] + 4.0,
                2.2 * latent[:, 1] + 0.1 * latent[:, 2] - 3.0,
                0.8 * latent[:, 0] + 1.3 * latent[:, 2] + 7.0,
                -0.6 * latent[:, 1] + 0.4 * latent[:, 2] + 2.0,
            ])
            raw[0, 0] += 100.0 + n
            raw[1, 3] -= 85.0 + n
            raw[2, 1] = np.nan
            raw[n - 2, 4] = np.nan
            raw[n // 2, 2] = np.nan
            cases.append(raw)

        for raw in cases:
            expected = _reference_pca(raw)
            _write_input(raw_path, raw)
            if os.path.exists(output_path):
                os.remove(output_path)
            run_result = subprocess.run(
                [binary], cwd='/home/user', text=True,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
            )
            assert run_result.returncode == 0, 'The compiled pipeline failed while running:\n' + run_result.stdout
            actual = _read_strict_output(output_path, raw.shape[0])

            assert np.allclose(actual.mean(axis=0), 0.0, atol=2e-5), 'Projected output is not mean-centered.'
            # PCA eigenvector signs are arbitrary. Comparing row Gram matrices
            # verifies the projections while remaining invariant to sign choices.
            actual_gram = actual @ actual.T
            expected_gram = expected @ expected.T
            assert np.allclose(actual_gram, expected_gram, rtol=5e-5, atol=2e-4), \
                'Program output does not match imputation, population-sigma capping, and top-2 PCA.'
    finally:
        with open(raw_path, 'wb') as f:
            f.write(raw_backup)
        if output_existed:
            with open(output_path, 'wb') as f:
                f.write(output_backup)
        elif os.path.exists(output_path):
            os.remove(output_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
