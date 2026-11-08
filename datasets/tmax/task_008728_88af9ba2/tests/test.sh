#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import stat
import subprocess
import json
import re
import pytest
import h5py
import numpy as np

SOURCE_PATH = '/home/user/process_covs.cpp'
PROGRAM_PATH = '/home/user/process_covs'
RESULTS_PATH = '/home/user/results.csv'
H5_PATH = '/home/user/covariances.h5'


def get_matrices_from_h5(file_path):
    """Reads the matrices from the HDF5 file using a subprocess since h5py is installed in the env."""
    script = f"""
import h5py
import json

try:
    with h5py.File('{file_path}', 'r') as f:
        matrices = f['cov_matrices'][:].tolist()
    print(json.dumps(matrices))
except Exception as e:
    print(json.dumps({{"error": str(e)}}))
"""
    try:
        out = subprocess.check_output(['python3', '-c', script], text=True)
        data = json.loads(out)
        if 'error' in data:
            pytest.fail(f"Failed to read HDF5 file: {data['error']}")
        return data
    except subprocess.CalledProcessError:
        pytest.fail('Failed to execute python script to read HDF5 file.')


def cholesky_trace(A, lam):
    """Computes the trace of the Cholesky factor L of (A + lam * I) in pure Python."""
    n = len(A)
    L = [[0.0] * n for _ in range(n)]
    trace = 0.0
    for i in range(n):
        for j in range(i + 1):
            s = sum(L[i][k] * L[j][k] for k in range(j))
            if i == j:
                val = A[i][i] + lam - s
                if val <= 0:
                    return None
                L[i][j] = math.sqrt(val)
                trace += L[i][j]
            else:
                if L[j][j] == 0:
                    return None
                L[i][j] = (A[i][j] - s) / L[j][j]
    return trace


def first_successful_lambda(A):
    """Returns the first positive-definite value in the required 0.0001 sequence."""
    matrix = np.asarray(A, dtype=float)
    for step_number in range(100000):
        lam = step_number * 0.0001
        smallest_eigenvalue = np.linalg.eigvalsh(matrix + lam * np.eye(3))[0]
        if smallest_eigenvalue > 1e-12:
            return lam
    pytest.fail('No successful regularization value found within the verifier bound.')


def read_and_validate_csv(expected_matrices):
    assert os.path.isfile(RESULTS_PATH), 'The program did not create results.csv.'
    with open(RESULTS_PATH, 'r', newline='') as f:
        rows = list(csv.reader(f))

    assert rows and rows[0] == ['index', 'lambda', 'trace_L'], 'Incorrect CSV header.'
    assert len(rows) == len(expected_matrices) + 1, 'Incorrect number of CSV rows.'

    for i, fields in enumerate(rows[1:]):
        assert len(fields) == 3, f'Row {i} does not have exactly three columns.'
        assert fields[0] == str(i), f'Expected index {i}, got {fields[0]}.'
        assert re.fullmatch(r'^[+-]?[0-9]+[.][0-9]{4}$', fields[1]), \
            f'Lambda on row {i} is not written to four decimal places.'
        assert re.fullmatch(r'^[+-]?[0-9]+[.][0-9]{4}$', fields[2]), \
            f'Trace on row {i} is not written to four decimal places.'

        lam = float(fields[1])
        trace_l = float(fields[2])
        assert math.isfinite(lam) and math.isfinite(trace_l), f'Non-finite value on row {i}.'

        expected_lam = first_successful_lambda(expected_matrices[i])
        assert fields[1] == f'{expected_lam:.4f}', \
            f'Matrix {i}: expected first successful lambda {expected_lam:.4f}, got {fields[1]}.'
        expected_trace = cholesky_trace(expected_matrices[i], expected_lam)
        assert expected_trace is not None
        assert math.isclose(trace_l, expected_trace, rel_tol=1e-3, abs_tol=1e-3), \
            f'Matrix {i}: expected trace about {expected_trace:.4f}, got {trace_l:.4f}.'


def run_program():
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    completed = subprocess.run(
        [PROGRAM_PATH], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert completed.returncode == 0, \
        f'process_covs exited with {completed.returncode}: {completed.stderr}'
    assert os.path.isfile(RESULTS_PATH), 'process_covs did not produce results.csv.'


@pytest.fixture(scope='module', autouse=True)
def execute_and_exercise_program():
    assert os.path.isfile(SOURCE_PATH) and not os.path.islink(SOURCE_PATH), \
        'process_covs.cpp is missing or is not a regular submitted source file.'
    assert stat.S_ISREG(os.stat(SOURCE_PATH).st_mode) and os.path.getsize(SOURCE_PATH) > 0, \
        'process_covs.cpp is empty or not a regular file.'
    assert os.path.isfile(PROGRAM_PATH) and not os.path.islink(PROGRAM_PATH), \
        'The compiled process_covs program is missing or is not a regular file.'
    assert os.access(PROGRAM_PATH, os.X_OK), 'process_covs is not executable.'
    with open(PROGRAM_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'process_covs is not a compiled ELF program.'
    assert os.path.isfile(H5_PATH), 'covariances.h5 is missing.'

    with open(H5_PATH, 'rb') as f:
        original_h5 = f.read()

    q, _ = np.linalg.qr(np.array([
        [1.0, 2.0, 3.0],
        [2.0, -1.0, 0.5],
        [0.25, 1.5, -2.0],
    ]))
    alternate_matrices = np.array([
        np.diag([1.25, 2.5, 4.0]),
        np.diag([1.0, 2.0, 0.0]),
        np.diag([0.8, 1.7, -0.00015]),
        q @ np.diag([-0.01234, 0.7, 2.3]) @ q.T,
    ], dtype=np.float64)

    try:
        with h5py.File(H5_PATH, 'w') as f:
            f.create_dataset('cov_matrices', data=alternate_matrices, dtype='f8')
        run_program()
        read_and_validate_csv(alternate_matrices.tolist())
    finally:
        with open(H5_PATH, 'wb') as f:
            f.write(original_h5)
        run_program()


def test_results_csv_exists_and_format():
    """Check that results.csv exists and has the correct format."""
    results_path = '/home/user/results.csv'
    assert os.path.isfile(results_path), f'The results file does not exist at {results_path}'

    with open(results_path, 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, 'The results.csv file is empty.'
    assert rows[0] == ['index', 'lambda', 'trace_L'], f'Incorrect header in results.csv: {rows[0]}'
    assert len(rows) == 6, f'Expected 5 data rows, got {len(rows) - 1}'
    for i, row in enumerate(rows[1:]):
        assert len(row) == 3, f'Row {i} does not have exactly three columns.'
        assert re.fullmatch(r'^[+-]?[0-9]+[.][0-9]{4}$', row[1]), 'Lambda must have four decimals.'
        assert re.fullmatch(r'^[+-]?[0-9]+[.][0-9]{4}$', row[2]), 'Trace must have four decimals.'


def test_results_values():
    """Verify the lambda values and the computed traces."""
    results_path = '/home/user/results.csv'
    h5_path = '/home/user/covariances.h5'

    assert os.path.isfile(results_path), 'results.csv is missing.'
    assert os.path.isfile(h5_path), 'covariances.h5 is missing.'

    matrices = get_matrices_from_h5(h5_path)
    assert len(matrices) == 5, 'Expected 5 matrices in the HDF5 file.'

    with open(results_path, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    for i, row in enumerate(rows):
        idx = int(row['index'])
        assert idx == i, f'Expected index {i}, got {idx}'

        lam = float(row['lambda'])
        trace_l = float(row['trace_L'])
        assert math.isfinite(lam) and math.isfinite(trace_l), f'Matrix {i} has a non-finite result.'

        if i == 0:
            assert math.isclose(lam, 0.0, abs_tol=1e-5), f'Matrix 0 is strongly SPD. Expected lambda=0.0, got {lam}'
        elif i == 1:
            assert lam >= 0.0, f'Matrix 1 is singular. Expected lambda >= 0.0, got {lam}'
        elif i == 2:
            assert lam >= 0.01, f'Matrix 2 is negative definite. Expected lambda >= 0.01, got {lam}'
        elif i == 3:
            assert math.isclose(lam, 0.0, abs_tol=1e-5), f'Matrix 3 is strongly SPD. Expected lambda=0.0, got {lam}'
        elif i == 4:
            assert lam >= 0.0001, f'Matrix 4 is near singular. Expected lambda >= 0.0001, got {lam}'

        expected_lam = first_successful_lambda(matrices[i])
        assert row['lambda'] == f'{expected_lam:.4f}', \
            f'Matrix {i}: expected first successful lambda {expected_lam:.4f}, got {row["lambda"]}'

        expected_trace = cholesky_trace(matrices[i], lam)
        assert expected_trace is not None, f'Matrix {i} with lambda {lam} is still not positive definite.'

        assert math.isclose(trace_l, expected_trace, rel_tol=1e-3, abs_tol=1e-3), \
            f'Trace mismatch for matrix {i}: expected ~{expected_trace:.4f}, got {trace_l:.4f}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
