#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import math
import os
import runpy
import sys

import numpy as np


def transpose(A):
    return [list(x) for x in zip(*A)]


def dot(v1, v2):
    return sum(x * y for x, y in zip(v1, v2))


def norm(v):
    return math.sqrt(sum(x**2 for x in v))


def matmul(A, B):
    B_T = transpose(B)
    return [[dot(row, col) for col in B_T] for row in A]


def qr_decomposition(A):
    n = len(A[0])
    R = [[0.0] * n for _ in range(n)]
    V = transpose(A)
    U = []
    for i in range(n):
        u = list(V[i])
        for j in range(i):
            R[j][i] = dot(U[j], V[i])
            u = [u_k - R[j][i] * U[j][k] for k, u_k in enumerate(u)]
        R[i][i] = norm(u)
        U.append([x / R[i][i] for x in u])
    return transpose(U), R


def solve_upper_triangular(R, b):
    n = len(R)
    x = [0.0] * n
    for i in range(n - 1, -1, -1):
        x[i] = b[i]
        for j in range(i + 1, n):
            x[i] -= R[i][j] * x[j]
        x[i] /= R[i][i]
    return x


def read_csv(filepath):
    with open(filepath, 'r') as f:
        return [[float(v) for v in row] for row in csv.reader(f) if row]


def expected_values(A, B):
    Q, R = qr_decomposition(A)
    Q_T_B = matmul(transpose(Q), B)
    X_expected = transpose([
        solve_upper_triangular(R, col) for col in transpose(Q_T_B)
    ])
    B_pred = matmul(A, X_expected)
    rss_expected = [
        sum((B[i][j] - B_pred[i][j])**2 for i in range(len(B)))
        for j in range(len(B[0]))
    ]
    return X_expected, rss_expected


def validate_outputs(A, B):
    conc_path = '/home/user/concentrations.csv'
    rss_path = '/home/user/rss.txt'
    assert os.path.isfile(conc_path), f'Missing {conc_path}'
    assert os.path.isfile(rss_path), f'Missing {rss_path}'

    X_expected, rss_expected = expected_values(A, B)
    X_user = read_csv(conc_path)
    with open(rss_path, 'r') as f:
        rss_user = [float(line.strip()) for line in f if line.strip()]

    assert len(X_user) == len(X_expected), \
        f'Concentration matrix has {len(X_user)} rows, expected {len(X_expected)}'
    for i in range(len(X_expected)):
        assert len(X_user[i]) == len(X_expected[i]), \
            f'Concentration matrix row {i} has {len(X_user[i])} columns, expected {len(X_expected[i])}'
        for j in range(len(X_expected[i])):
            assert math.isclose(X_user[i][j], X_expected[i][j], abs_tol=1e-5), \
                f'Concentration mismatch at ({i}, {j}): expected {X_expected[i][j]:.6f}, got {X_user[i][j]:.6f}'

    assert len(rss_user) == len(rss_expected), \
        f'RSS list has {len(rss_user)} values, expected {len(rss_expected)}'
    for j in range(len(rss_expected)):
        assert math.isclose(rss_user[j], rss_expected[j], abs_tol=1e-5), \
            f'RSS mismatch at index {j}: expected {rss_expected[j]:.6f}, got {rss_user[j]:.6f}'
    return X_user


def inspect_source(path):
    assert os.path.isfile(path), f'Missing {path}'
    with open(path, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=path)
    prohibited = {'lstsq', 'pinv', 'least_squares', 'lsqr', 'lsmr'}
    used = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Name):
            used.add(node.id)
        elif isinstance(node, ast.Attribute):
            used.add(node.attr)
        elif isinstance(node, ast.Constant) and isinstance(node.value, str):
            used.add(node.value)
    bad = sorted(prohibited & used)
    assert not bad, f'Prohibited least-squares solver(s) referenced: {bad}'


def run_submission(sabotage_qr=False):
    script = '/home/user/solve.py'
    for path in ('/home/user/concentrations.csv', '/home/user/rss.txt'):
        if os.path.exists(path):
            os.remove(path)

    original_qr = np.linalg.qr
    originals = {}
    qr_calls = []

    def checked_qr(*args, **kwargs):
        qr_calls.append(1)
        result = original_qr(*args, **kwargs)
        if not sabotage_qr:
            return result
        Q, R = result
        R = np.array(R, copy=True)
        R[0, 0] *= 1.2
        return Q, R

    def forbidden(*args, **kwargs):
        raise AssertionError('A prohibited high-level least-squares solver was called')

    for name in ('lstsq', 'pinv'):
        originals[name] = getattr(np.linalg, name)
        setattr(np.linalg, name, forbidden)
    np.linalg.qr = checked_qr
    old_argv = sys.argv
    try:
        sys.argv = [script]
        runpy.run_path(script, run_name='__main__')
    finally:
        sys.argv = old_argv
        np.linalg.qr = original_qr
        for name, value in originals.items():
            setattr(np.linalg, name, value)

    assert qr_calls, 'solve.py did not call numpy.linalg.qr'


def make_challenge_data():
    rows = []
    for i in range(50):
        t = (i + 1) / 51.0
        rows.append([1.0, t, t * t, math.sin(4.7 * t) + 0.2 * t])
    X = [
        [0.21, 0.42, 0.63, 0.84, 0.35],
        [0.73, 0.18, 0.54, 0.31, 0.92],
        [0.15, 0.67, 0.29, 0.76, 0.48],
        [0.88, 0.37, 0.61, 0.24, 0.57],
    ]
    B = matmul(rows, X)
    for i in range(50):
        for j in range(5):
            B[i][j] += 0.001 * math.sin((i + 2) * (j + 3))
    return rows, B


def test_concentrations_and_rss():
    pure_path = '/home/user/pure_components.csv'
    spectra_path = '/home/user/spectra.csv'
    script_path = '/home/user/solve.py'

    assert os.path.isfile(pure_path), f'Missing {pure_path}'
    assert os.path.isfile(spectra_path), f'Missing {spectra_path}'
    inspect_source(script_path)

    with open(pure_path, 'rb') as f:
        original_pure = f.read()
    with open(spectra_path, 'rb') as f:
        original_spectra = f.read()

    A_challenge, B_challenge = make_challenge_data()
    X_expected_challenge, _ = expected_values(A_challenge, B_challenge)

    try:
        np.savetxt(pure_path, np.asarray(A_challenge), delimiter=',')
        np.savetxt(spectra_path, np.asarray(B_challenge), delimiter=',')

        # A script that genuinely uses the QR factors must react when R is perturbed.
        run_submission(sabotage_qr=True)
        assert os.path.isfile('/home/user/concentrations.csv'), 'solve.py did not create concentrations.csv'
        X_probe = read_csv('/home/user/concentrations.csv')
        assert len(X_probe) == 4 and all(len(row) == 5 for row in X_probe), \
            'Perturbed QR run produced an invalid concentration matrix'
        assert any(
            abs(X_probe[i][j] - X_expected_challenge[i][j]) > 1e-4
            for i in range(4) for j in range(5)
        ), 'Outputs do not depend on the factors returned by numpy.linalg.qr'

        # Exercise the submitted script on verifier-generated inputs.
        run_submission(sabotage_qr=False)
        validate_outputs(A_challenge, B_challenge)
    finally:
        with open(pure_path, 'wb') as f:
            f.write(original_pure)
        with open(spectra_path, 'wb') as f:
            f.write(original_spectra)

    # Preserve the original assertions on the supplied data and leave final outputs for it.
    run_submission(sabotage_qr=False)
    A = read_csv(pure_path)
    B = read_csv(spectra_path)
    validate_outputs(A, B)


if __name__ == '__main__':
    test_concentrations_and_rss()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
