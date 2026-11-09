#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import pytest

def jacobi_eigenvalue_algorithm(A, iters=100):
    n = len(A)
    V = [[1.0 if i == j else 0.0 for j in range(n)] for i in range(n)]
    A_copy = [row[:] for row in A]

    for _ in range(iters):
        max_val = -1.0
        p, q = 0, 0
        for i in range(n):
            for j in range(i+1, n):
                if abs(A_copy[i][j]) > max_val:
                    max_val = abs(A_copy[i][j])
                    p, q = i, j
        if max_val < 1e-12:
            break

        app = A_copy[p][p]
        aqq = A_copy[q][q]
        apq = A_copy[p][q]

        if apq == 0:
            continue

        theta = (aqq - app) / (2.0 * apq)
        t = 1.0 / (abs(theta) + math.sqrt(theta**2 + 1.0))
        if theta < 0: 
            t = -t

        c = 1.0 / math.sqrt(t**2 + 1.0)
        s = t * c

        for i in range(n):
            if i != p and i != q:
                api = A_copy[p][i]
                aqi = A_copy[q][i]
                A_copy[p][i] = A_copy[i][p] = c * api - s * aqi
                A_copy[q][i] = A_copy[i][q] = s * api + c * aqi

        app_new = c**2 * app + s**2 * aqq - 2*s*c*apq
        aqq_new = s**2 * app + c**2 * aqq + 2*s*c*apq
        A_copy[p][p] = app_new
        A_copy[q][q] = aqq_new
        A_copy[p][q] = A_copy[q][p] = 0.0

        for i in range(n):
            vip = V[i][p]
            viq = V[i][q]
            V[i][p] = c * vip - s * viq
            V[i][q] = s * vip + c * viq

    eigenvalues = [A_copy[i][i] for i in range(n)]
    # eigenvectors are the columns of V

    # Sort eigenvalues in descending order
    idx = sorted(range(n), key=lambda x: eigenvalues[x], reverse=True)
    eigenvalues = [eigenvalues[i] for i in idx]
    eigenvectors = [[V[i][j] for j in idx] for i in range(n)]

    return eigenvalues, eigenvectors

def compute_truth():
    pdb_path = "/home/user/input.pdb"
    points = []
    with open(pdb_path, 'r') as f:
        for line in f:
            if line.startswith("ATOM  "):
                x = float(line[30:38])
                y = float(line[38:46])
                z = float(line[46:54])
                points.append((x, y, z))

    # Sort points
    points = sorted(points, key=lambda p: (p[0], p[1], p[2]))
    N = len(points)

    # Centroid
    cx = sum(p[0] for p in points) / N
    cy = sum(p[1] for p in points) / N
    cz = sum(p[2] for p in points) / N
    centroid = (cx, cy, cz)

    # Covariance
    C = [[0.0]*3 for _ in range(3)]
    centered = [(p[0]-cx, p[1]-cy, p[2]-cz) for p in points]

    for p in centered:
        C[0][0] += p[0]*p[0]
        C[0][1] += p[0]*p[1]
        C[0][2] += p[0]*p[2]
        C[1][0] += p[1]*p[0]
        C[1][1] += p[1]*p[1]
        C[1][2] += p[1]*p[2]
        C[2][0] += p[2]*p[0]
        C[2][1] += p[2]*p[1]
        C[2][2] += p[2]*p[2]

    # SVD
    singular_values, U = jacobi_eigenvalue_algorithm(C)

    # Dominant axis
    v = [U[0][0], U[1][0], U[2][0]]
    if v[0] < 0:
        v = [-v[0], -v[1], -v[2]]
    elif v[0] == 0 and v[1] < 0:
        v = [-v[0], -v[1], -v[2]]

    # Integral
    def density(px, py, pz):
        val = 0.0
        for p in points:
            sq_dist = (p[0]-px)**2 + (p[1]-py)**2 + (p[2]-pz)**2
            val += math.exp(-0.1 * sq_dist)
        return val

    t_vals = [-10.0 + i * (20.0 / 1000) for i in range(1001)]
    dt = 20.0 / 1000

    integral = 0.0
    for i, t in enumerate(t_vals):
        px = centroid[0] + t * v[0]
        py = centroid[1] + t * v[1]
        pz = centroid[2] + t * v[2]
        val = density(px, py, pz)
        weight = dt if (0 < i < 1000) else dt / 2.0
        integral += val * weight

    return centroid, singular_values, integral

@pytest.fixture(scope="module")
def truth():
    return compute_truth()

def test_centroid_file(truth):
    expected_centroid, _, _ = truth
    path = "/home/user/centroid.txt"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    parts = content.split(',')
    assert len(parts) == 3, f"Expected 3 comma-separated values in {path}, got {len(parts)}."

    for i, (actual_str, expected) in enumerate(zip(parts, expected_centroid)):
        actual = float(actual_str)
        assert math.isclose(actual, expected, rel_tol=1e-4, abs_tol=1e-4), \
            f"Centroid coordinate {i} mismatch. Expected ~{expected:.6f}, got {actual}."

def test_singular_values_file(truth):
    _, expected_singular_values, _ = truth
    path = "/home/user/singular_values.txt"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    parts = content.split(',')
    assert len(parts) == 3, f"Expected 3 comma-separated values in {path}, got {len(parts)}."

    for i, (actual_str, expected) in enumerate(zip(parts, expected_singular_values)):
        actual = float(actual_str)
        assert math.isclose(actual, expected, rel_tol=1e-4, abs_tol=1e-4), \
            f"Singular value {i} mismatch. Expected ~{expected:.6f}, got {actual}."

def test_integral_file(truth):
    _, _, expected_integral = truth
    path = "/home/user/integral.txt"
    assert os.path.exists(path), f"File {path} is missing."

    with open(path, "r") as f:
        content = f.read().strip()

    actual = float(content)
    assert math.isclose(actual, expected_integral, rel_tol=1e-4, abs_tol=1e-4), \
        f"Integral mismatch. Expected ~{expected_integral:.6f}, got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
